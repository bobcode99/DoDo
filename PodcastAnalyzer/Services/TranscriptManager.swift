//
//  TranscriptManager.swift
//  PodcastAnalyzer
//
//  Manages background transcript generation across the app
//

import AVFoundation
import SwiftData
import Foundation
import OSLog
import Speech

extension SFSpeechRecognizer {
  /// Async wrapper for `requestAuthorization` that is safe under
  /// MainActor-default isolation. The raw completion handler arrives on a TCC
  /// background queue; a closure literal formed in a MainActor context gets
  /// inferred @MainActor and trips dispatch_assert_queue when invoked there.
  /// Forming the closure inside this `nonisolated` function avoids the
  /// inference — resume is thread-safe by design.
  static nonisolated func requestAuthorizationStatus() async -> SFSpeechRecognizerAuthorizationStatus {
    await withCheckedContinuation { continuation in
      requestAuthorization { continuation.resume(returning: $0) }
    }
  }
}

/// Tracks the status of a transcript generation job
enum TranscriptJobStatus: Equatable {
  case queued
  case downloadingModel(progress: Double)
  case transcribing(progress: Double)
  case completed
  case failed(error: String)
}

/// Parallel-part progress for split (chunked) Apple Speech transcription.
/// Absent when the audio is short or the user disabled splitting (single pass).
struct TranscriptPartProgress: Equatable, Sendable {
  let completed: Int
  let total: Int
}

/// Represents a transcript generation job
struct TranscriptJob: Identifiable {
  let id: String  // podcastTitle + Unit Separator + episodeTitle (same format as episode keys)
  let episodeTitle: String
  let podcastTitle: String
  let audioPath: String
  let audioRemoteURL: String?  // Remote RSS audio URL — used by yap when episode not downloaded
  let language: String?
  let engine: TranscriptEngine?  // nil = use global Settings default
  var status: TranscriptJobStatus = .queued
  var yapServerJobID: String?    // Set once the yap HTTP job is accepted; used to cancel server-side
  var detectedLanguage: String?  // Populated by Whisper auto-detect before full transcription
  var partProgress: TranscriptPartProgress?  // Split-transcription part counts (Apple Speech, chunked)
  var phase: TranscriptionPhase?  // Current pipeline step (prepare/split/transcribe/merge)
  var timeoutSeconds: TimeInterval?  // Active timeout: yap = dynamic wall clock, local = stall limit
}

/// Manages background transcript generation with parallel processing.
///
/// Explicit `@MainActor` because all state (`activeJobs`, `pendingJobs`, etc.) drives
/// UI observation via `@Observable`.  Heavy work is delegated to `TranscriptService`
/// and `WhisperTranscriptService` (both actors), so `await`-ing their methods
/// automatically suspends the caller and runs on the actor's executor.
@available(iOS 17.0, *)
@MainActor
@Observable
class TranscriptManager {
  static let shared = TranscriptManager()

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranscriptManager")
  private let fileStorage = FileStorageManager.shared

  /// Set at launch so transcription can read each podcast's `transcriptionTerms`
  /// (the SpeechAnalyzer contextual-strings vocabulary) from SwiftData.
  private var modelContainer: ModelContainer?
  func setModelContainer(_ container: ModelContainer) { self.modelContainer = container }

  // Helper to create job ID matching episode key format
  private func makeJobId(podcastTitle: String, episodeTitle: String) -> String {
    EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
  }

  /// Per-podcast transcription vocabulary, looked up by title from SwiftData.
  /// Empty when no container is set or the podcast/terms aren't found.
  private func transcriptionTerms(for podcastTitle: String) -> [String] {
    guard let context = modelContainer?.mainContext else { return [] }
    var descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.title == podcastTitle }
    )
    descriptor.fetchLimit = 1
    return (try? context.fetch(descriptor))?.first?.transcriptionTerms ?? []
  }

  var activeJobs: [String: TranscriptJob] = [:]
  var isProcessing: Bool = false

  /// Jobs still in flight (queued / downloading model / transcribing). Shared so
  /// the Library, quick-access, and macOS transcribing badges don't each
  /// re-derive the same loop.
  var activeJobCount: Int {
    activeJobs.values.reduce(into: 0) { count, job in
      switch job.status {
      case .queued, .downloadingModel, .transcribing: count += 1
      case .completed, .failed: break
      }
    }
  }

  // Maximum concurrent transcript jobs
  private let maxConcurrentJobs: Int = {
    let processorCount = ProcessInfo.processInfo.processorCount
    return min(max(processorCount / 2, 2), 4)
  }()

  // Queue for pending jobs
  private var pendingJobs: [TranscriptJob] = []
  private var runningJobIds: Set<String> = []
  private var processingTasks: [String: Task<Void, Never>] = [:]

  // Session-scoped failure counter for yap auto-transcript.
  // After yapFailureLimit consecutive failures for a podcast, auto-queuing is paused
  // for that podcast until the next app launch (manual queue still works).
  private var yapConsecutiveFailures: [String: Int] = [:]
  private let yapFailureLimit = 3

  // Per-job timestamp of the last YAP progress update we forwarded to activeJobs.
  // Used to throttle high-frequency poll callbacks to ~4 Hz so the @Observable
  // dictionary doesn't invalidate every SwiftUI consumer on each tick.
  private var lastYapProgressUpdate: [String: Date] = [:]

  private static let speechDeniedError = String(localized: "Speech recognition permission denied. Enable in Settings > Privacy > Speech Recognition.")
  private static let speechRestrictedError = String(localized: "Speech recognition is restricted on this device.")

  private init() {}

  // No deinit needed — TranscriptManager is a singleton (static let shared)
  // that lives for the app's lifetime. Tasks are cancelled via cancelAll().

  // MARK: - Public API

  /// Queues a transcript generation job
  func queueTranscript(
    episodeTitle: String, podcastTitle: String, audioPath: String,
    audioRemoteURL: String? = nil, language: String?,
    engine: TranscriptEngine? = nil
  ) {
    let jobId = makeJobId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)

    if let existing = activeJobs[jobId] {
      if case .failed = existing.status {
        // Allow retry: remove the failed job so a new one can be queued
        activeJobs.removeValue(forKey: jobId)
        logger.info("Retrying failed transcript job for: \(episodeTitle)")
      } else {
        logger.info("Transcript job already exists for: \(episodeTitle)")
        return
      }
    }

    let job = TranscriptJob(
      id: jobId,
      episodeTitle: episodeTitle,
      podcastTitle: podcastTitle,
      audioPath: audioPath,
      audioRemoteURL: audioRemoteURL,
      language: language,
      engine: engine
    )

    pendingJobs.append(job)
    activeJobs[jobId] = job
    logger.info("Queued transcript job for: \(episodeTitle)")
    startProcessingIfNeeded()
  }

  /// Auto-enqueue variant that no-ops when the episode already has a caption file
  /// on disk. Use this from non-user-initiated paths (post-download hook, feed
  /// refresh, opt-in backfill). Manual "Generate Transcript" buttons should keep
  /// calling `queueTranscript` so the user can intentionally replace a transcript.
  func queueAutoTranscript(
    episodeTitle: String, podcastTitle: String, audioPath: String,
    audioRemoteURL: String? = nil, language: String?,
    engine: TranscriptEngine? = nil
  ) {
    let jobId = makeJobId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
    if let existing = activeJobs[jobId] {
      switch existing.status {
      case .queued, .downloadingModel, .transcribing, .completed:
        return  // already in flight or done; let queueTranscript handle retry of .failed
      case .failed:
        break
      }
    }

    Task { [weak self] in
      guard let self else { return }
      let exists = await FileStorageManager.shared.captionFileExists(
        for: episodeTitle, podcastTitle: podcastTitle)
      if exists {
        self.logger.info("Auto-transcript skipped — caption already exists: \(episodeTitle)")
        return
      }
      self.queueTranscript(
        episodeTitle: episodeTitle,
        podcastTitle: podcastTitle,
        audioPath: audioPath,
        audioRemoteURL: audioRemoteURL,
        language: language,
        engine: engine
      )
    }
  }

  /// Checks if a transcript is being generated for an episode. Every pending
  /// and running job has an `activeJobs` entry, so its status is authoritative.
  func isGenerating(episodeTitle: String, podcastTitle: String) -> Bool {
    let jobId = makeJobId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
    switch activeJobs[jobId]?.status {
    case .queued, .downloadingModel, .transcribing: return true
    case .completed, .failed, nil: return false
    }
  }

  /// Cancels all pending and running transcript jobs.
  func cancelAll() {
    for (jobId, task) in processingTasks {
      if let yapServerJobID = activeJobs[jobId]?.yapServerJobID {
        cancelYapServerJob(serverJobID: yapServerJobID)
      }
      task.cancel()
    }
    processingTasks.removeAll()
    runningJobIds.removeAll()
    pendingJobs.removeAll()
    activeJobs.removeAll()
    isProcessing = false
    logger.info("All transcript jobs cancelled")
  }

  /// Cancels a pending or active transcript job
  func cancelJob(episodeTitle: String, podcastTitle: String) {
    let jobId = makeJobId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)

    pendingJobs.removeAll { $0.id == jobId }

    // Cancel server-side yap job if one was submitted
    if let yapServerJobID = activeJobs[jobId]?.yapServerJobID {
      cancelYapServerJob(serverJobID: yapServerJobID)
    }

    activeJobs.removeValue(forKey: jobId)

    if runningJobIds.contains(jobId) {
      processingTasks[jobId]?.cancel()
      processingTasks.removeValue(forKey: jobId)
      runningJobIds.remove(jobId)
      logger.info("Cancelled running transcript job for: \(episodeTitle)")

      if runningJobIds.isEmpty && pendingJobs.isEmpty {
        isProcessing = false
      }
    }
  }

  // MARK: - Auto-transcribe engine resolution

  /// Resolution outcome for `resolveAutoTranscribeEngine`. Callers should treat
  /// `.blocked` as a UI affordance: show the one-time battery warning and, on
  /// user opt-in, call `setAllowLocalOnBattery(true)` and try again.
  enum AutoTranscribeEngineDecision: Sendable {
    case yap
    case local(TranscriptEngine)
    case blocked(reason: String)
  }

  /// Session-scoped consent to run local transcription on battery. Not persisted
  /// — the user must re-confirm every cold launch, so the warning isn't lost.
  private(set) var allowLocalOnBattery: Bool = false

  /// Set by the one-time battery-warning dialog. Resets to `false` at next launch.
  func setAllowLocalOnBattery(_ allow: Bool) {
    allowLocalOnBattery = allow
    if allow {
      logger.info("User opted in to local transcription on battery for this session.")
    }
  }

  /// Resolves the engine for an auto-enqueue path (post-download hook, feed
  /// refresh) and applies non-UI gates: Low Power Mode skip, YAP per-podcast
  /// failure cooldown. Returns the engine to enqueue with, or nil to skip.
  /// Call sites should treat nil as "don't auto-enqueue right now" — *not* as
  /// an error worth surfacing.
  func engineForAutoEnqueue(podcastTitle: String) -> TranscriptEngine? {
    guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return nil }
    switch resolveAutoTranscribeEngine() {
    case .yap:
      return canAutoQueueYap(podcastTitle: podcastTitle) ? .yapServer : nil
    case .local(let local):
      return local
    case .blocked:
      return nil
    }
  }

  /// Decides which engine should handle a new auto-transcribe job *right now*,
  /// given the current YAP server config and device power state. Pure function
  /// — does not enqueue. Call this before `queueTranscript(...)` so that an
  /// auto-enqueue path (feed refresh, post-download hook, backfill sheet) can
  /// surface the battery warning before consuming the user's battery.
  func resolveAutoTranscribeEngine() -> AutoTranscribeEngineDecision {
    // 1. Prefer YAP when configured. Battery is irrelevant for YAP (work happens server-side).
    if !YapServerSettings.shared.serverURL.isEmpty {
      return .yap
    }

    // 2. No YAP — fall back to local engine. Gated by charging or session opt-in.
    let local = TranscriptEngine(
      rawValue: UserDefaults.standard.string(forKey: "transcriptEngine") ?? ""
    ) ?? .appleSpeech

    #if os(iOS)
    if PowerMonitor.shared.isCharging || allowLocalOnBattery {
      return .local(local)
    }
    return .blocked(reason: "On battery and YAP server is not configured.")
    #else
    // macOS: PowerMonitor reports !isCharging always; treat as unrestricted.
    return .local(local)
    #endif
  }

  // MARK: - Processing

  private func startProcessingIfNeeded() {
    while runningJobIds.count < maxConcurrentJobs && !pendingJobs.isEmpty {
      let job = pendingJobs.removeFirst()
      runningJobIds.insert(job.id)
      isProcessing = true

      let task = Task { [weak self] in
        guard let self else { return }
        await self.processJob(job)
      }
      processingTasks[job.id] = task
    }
  }

  /// Yap-server timeout scaled to episode length: ≤1h → 3 min, 2h → 5 min,
  /// capped at 10 min. Unknown duration → 5 min.
  /// ponytail: linear duration/24 hits both requested anchors; tune the
  /// divisor if server throughput changes.
  nonisolated static func yapTimeout(forDuration duration: TimeInterval?) -> TimeInterval {
    guard let duration, duration.isFinite, duration > 0 else { return 300 }
    return min(max(duration / 24, 180), 600)
  }

  /// Local engines (Apple Speech / Whisper) can be slower than real time on
  /// old hardware, so a wall-clock cap would kill legitimate runs. Instead,
  /// treat "no progress event for this long" as a hang.
  private static let localStallSeconds: TimeInterval = 300

  /// Wraps a local-engine progress stream so a stall — no element arriving
  /// within `stallSeconds` — throws instead of hanging the job forever.
  private nonisolated static func withStallTimeout<Element: Sendable>(
    _ stream: AsyncThrowingStream<Element, Error>,
    stallSeconds: TimeInterval,
    label: String
  ) -> AsyncThrowingStream<Element, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        // Single consumer task; nonisolated(unsafe) silences the false
        // capture-mutation diagnostic from the per-element race below.
        nonisolated(unsafe) var iterator = stream.makeAsyncIterator()
        do {
          while true {
            let element = try await withThrowingTaskGroup(of: Element?.self) { group in
              group.addTask { try await iterator.next() }
              group.addTask {
                try await Task.sleep(for: .seconds(stallSeconds))
                throw NSError(
                  domain: "TranscriptManager", code: 7,
                  userInfo: [NSLocalizedDescriptionKey:
                    "\(label) stalled — no progress for \(Int(stallSeconds / 60)) minutes."]
                )
              }
              let value = try await group.next()!
              group.cancelAll()
              return value
            }
            guard let element else { break }
            continuation.yield(element)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private func processJob(_ job: TranscriptJob) async {
    var updatedJob = job
    updatedJob.status = .downloadingModel(progress: 0)
    activeJobs[job.id] = updatedJob

    let engine = job.engine ?? TranscriptEngine(
      rawValue: UserDefaults.standard.string(forKey: "transcriptEngine") ?? ""
    ) ?? .appleSpeech

    do {
      let audioURL = URL(fileURLWithPath: job.audioPath)
      let fileExists = FileManager.default.fileExists(atPath: job.audioPath)

      // Non-yap engines always need the local file
      if engine != .yapServer && !fileExists {
        throw NSError(
          domain: "TranscriptManager", code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Audio file not found: \(job.audioPath)"]
        )
      }

      switch engine {

      // MARK: Apple Speech path
      case .appleSpeech:
        // Check speech recognition permission
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        switch authStatus {
        case .denied:
          throw NSError(
            domain: "TranscriptManager", code: 5,
            userInfo: [NSLocalizedDescriptionKey: Self.speechDeniedError]
          )
        case .restricted:
          throw NSError(
            domain: "TranscriptManager", code: 6,
            userInfo: [NSLocalizedDescriptionKey: Self.speechRestrictedError]
          )
        case .notDetermined:
          // Request permission
          let granted = await SFSpeechRecognizer.requestAuthorizationStatus() == .authorized
          if !granted {
            throw NSError(
              domain: "TranscriptManager", code: 5,
              userInfo: [NSLocalizedDescriptionKey: Self.speechDeniedError]
            )
          }
        case .authorized:
          break
        @unknown default:
          break
        }

        try Task.checkCancellation()

        // Bias on-device recognition toward this show's proper nouns / jargon,
        // from the per-podcast Transcription Context vocabulary (PodcastInfoModel).
        let contextTerms = transcriptionTerms(for: job.podcastTitle)
        let contextualStrings = TranscriptService.buildContextualStrings(
          podcastTitle: job.podcastTitle, terms: contextTerms)
        let transcriptService = TranscriptService(
          language: job.language ?? "en-us", contextualStrings: contextualStrings)

        let modelReady = await transcriptService.isModelReady()
        if !modelReady {
          for await progress in await transcriptService.setupAndInstallAssets() {
            activeJobs[job.id]?.status = .downloadingModel(progress: progress)
          }
        } else {
          for await _ in await transcriptService.setupAndInstallAssets() {}
        }

        try Task.checkCancellation()

        guard await transcriptService.isInitialized() else {
          let setupError = await transcriptService.getSetupError()
          let detail = setupError?.localizedDescription ?? "Unknown error"
          throw NSError(
            domain: "TranscriptManager", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Apple Speech service: \(detail)"]
          )
        }

        try Task.checkCancellation()
        activeJobs[job.id]?.status = .transcribing(progress: 0)
        activeJobs[job.id]?.timeoutSeconds = Self.localStallSeconds

        // Single-pass when the user turned off splitting; otherwise chunked
        // parallel parts (which itself falls back to single-pass under 1 min).
        let splitLongAudio = SubtitleSettingsManager.shared.splitLongAudio
        let progressStream = splitLongAudio
          ? await transcriptService.audioToSRTChunkedWithProgress(inputFile: audioURL)
          : await transcriptService.audioToSRTWithProgress(inputFile: audioURL)

        var finalSRTContent: String?
        var lastUIUpdate = Date.distantPast
        for try await progressUpdate in Self.withStallTimeout(
          progressStream, stallSeconds: Self.localStallSeconds, label: "Apple Speech"
        ) {
          let parts = progressUpdate.totalParts > 1
            ? TranscriptPartProgress(
                completed: progressUpdate.completedParts, total: progressUpdate.totalParts)
            : nil
          if progressUpdate.isComplete {
            finalSRTContent = progressUpdate.srtContent
            activeJobs[job.id]?.partProgress = parts
            activeJobs[job.id]?.phase = progressUpdate.phase
            activeJobs[job.id]?.status = .transcribing(progress: 1.0)
          } else {
            let now = Date()
            // Always forward phase transitions promptly (they're rare); throttle
            // only the high-frequency percentage updates.
            let phaseChanged = activeJobs[job.id]?.phase != progressUpdate.phase
            if phaseChanged || now.timeIntervalSince(lastUIUpdate) >= 0.25 {
              activeJobs[job.id]?.partProgress = parts
              activeJobs[job.id]?.phase = progressUpdate.phase
              activeJobs[job.id]?.status = .transcribing(progress: progressUpdate.progress)
              lastUIUpdate = now
            }
          }
        }

        guard let srtContent = finalSRTContent else {
          throw NSError(
            domain: "TranscriptManager", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Transcription produced no content"]
          )
        }

        _ = try await fileStorage.saveCaptionFile(
          content: srtContent,
          episodeTitle: job.episodeTitle,
          podcastTitle: job.podcastTitle
        )

      // MARK: Whisper path (WhisperKit)
      case .whisper:
        let modelVariant = WhisperModelManager.shared.selectedModel

        if !WhisperModelManager.modelExistsOnDisk(modelVariant) {
          do {
            try await WhisperTranscriptService.downloadModel(
              variant: modelVariant,
              onProgress: { [weak self] progress in
                Task { @MainActor in
                  self?.activeJobs[job.id]?.status = .downloadingModel(progress: progress)
                }
              }
            )
          } catch is CancellationError {
            throw CancellationError()
          } catch {
            throw NSError(
              domain: "TranscriptManager", code: 4,
              userInfo: [
                NSLocalizedDescriptionKey:
                  "Whisper model download failed: \(error.localizedDescription)"
              ]
            )
          }
        }

        try Task.checkCancellation()
        activeJobs[job.id]?.status = .transcribing(progress: 0)
        activeJobs[job.id]?.phase = .transcribing
        activeJobs[job.id]?.timeoutSeconds = Self.localStallSeconds

        let whisperService = WhisperTranscriptService()
        var finalSRTContent: String?
        var lastUIUpdate = Date.distantPast

        for try await progressUpdate in Self.withStallTimeout(
          await whisperService.audioToSRTWithProgress(
            inputFile: audioURL,
            modelVariant: modelVariant,
            language: job.language),
          stallSeconds: Self.localStallSeconds, label: "Whisper"
        ) {
          // Capture detected language as soon as Whisper reports it.
          if let lang = progressUpdate.detectedLanguage {
            activeJobs[job.id]?.detectedLanguage = lang
          }
          if progressUpdate.isComplete {
            finalSRTContent = progressUpdate.srtContent
            activeJobs[job.id]?.status = .transcribing(progress: 1.0)
          } else {
            let now = Date()
            if now.timeIntervalSince(lastUIUpdate) >= 0.25 {
              activeJobs[job.id]?.status = .transcribing(progress: progressUpdate.progress)
              lastUIUpdate = now
            }
          }
        }

        guard let srtContent = finalSRTContent else {
          throw NSError(
            domain: "TranscriptManager", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Whisper transcription produced no content"]
          )
        }

        _ = try await fileStorage.saveCaptionFile(
          content: srtContent,
          episodeTitle: job.episodeTitle,
          podcastTitle: job.podcastTitle
        )

      // MARK: Yap Server path
      case .yapServer:
        // No model download needed — jump straight to transcribing
        activeJobs[job.id]?.status = .transcribing(progress: 0)

        logger.info("[YapServer] job.language=\(job.language ?? "<nil>") for \(job.episodeTitle)")

        let serverURL = await MainActor.run { YapServerSettings.shared.serverURL }
        let apiKey = await MainActor.run { YapServerSettings.shared.apiKey }
        let key = apiKey.isEmpty ? nil : apiKey

        // Dynamic timeout scaled to episode length (see yapTimeout).
        let audioDuration: TimeInterval? = fileExists
          ? try? await AVURLAsset(url: audioURL).load(.duration).seconds
          : nil
        let timeout = Self.yapTimeout(forDuration: audioDuration)
        activeJobs[job.id]?.timeoutSeconds = timeout

        // Forward the global subtitle settings so Yap uses the same music
        // detection behavior as the local Apple Speech path.
        let detectMusic = await MainActor.run { SubtitleSettingsManager.shared.enableMusicDetection }
        let musicSensitivity = await MainActor.run {
          SubtitleSettingsManager.shared.musicDetectionSensitivity.rawValue
        }

        guard let base = URL(string: serverURL) else {
          throw YapError.invalidServerURL
        }

        let yapService = YapTranscriptService()
        let jobID = job.id

        // Submit first, then store the server job ID synchronously on the @MainActor
        // before polling begins — this eliminates the race where cancel() fires
        // while yapServerJobID is still nil.
        let yapJobID: String
        if fileExists {
          yapJobID = try await yapService.submitJob(
            audioURL: audioURL, locale: job.language, baseURL: base, apiKey: key,
            name: job.episodeTitle,
            detectMusic: detectMusic,
            musicSensitivity: musicSensitivity)
        } else if let remoteURLString = job.audioRemoteURL, !remoteURLString.isEmpty {
          yapJobID = try await yapService.submitRemoteURLJob(
            remoteURL: remoteURLString, locale: job.language, baseURL: base, apiKey: key,
            name: job.episodeTitle,
            detectMusic: detectMusic,
            musicSensitivity: musicSensitivity)
        } else {
          throw NSError(
            domain: "TranscriptManager", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "No local file or remote URL available for yap transcription"]
          )
        }

        // Back on @MainActor — store before polling so cancelJob() can reach the server
        activeJobs[job.id]?.yapServerJobID = yapJobID
        logger.info("[YapServer] server job id=\(yapJobID) stored for \(job.episodeTitle)")

        try Task.checkCancellation()

        let onProgress: @Sendable (Double) -> Void = { [self] progress in
          Task { [self] in
            await self.setYapProgress(jobID: jobID, progress: progress)
          }
        }

        let srtContent = try await yapService.streamEvents(
          jobID: yapJobID, baseURL: base, apiKey: key, timeout: timeout, onProgress: onProgress
        )

        activeJobs[job.id]?.status = .transcribing(progress: 1.0)
        yapConsecutiveFailures[job.podcastTitle] = 0

        _ = try await fileStorage.saveCaptionFile(
          content: srtContent,
          episodeTitle: job.episodeTitle,
          podcastTitle: job.podcastTitle
        )
      }

      // MARK: Completion (shared)
      activeJobs[job.id]?.status = .completed
      logger.info("Transcript completed for: \(job.episodeTitle)")

      try? await Task.sleep(for: .seconds(3))
      activeJobs.removeValue(forKey: job.id)

    } catch is CancellationError {
      activeJobs.removeValue(forKey: job.id)
      logger.info("Transcript cancelled for: \(job.episodeTitle)")
    } catch {
      // `engine` resolved at the top of processJob is still in scope here.
      let message = Self.describeFailure(error, engine: engine)
      activeJobs[job.id]?.status = .failed(error: message)
      logger.error("Transcript failed for \(job.episodeTitle) [\(engine.rawValue)]: \(error.localizedDescription, privacy: .public)")
      if engine == .yapServer {
        yapConsecutiveFailures[job.podcastTitle, default: 0] += 1
      }
    }

    runningJobIds.remove(job.id)
    processingTasks.removeValue(forKey: job.id)
    if runningJobIds.isEmpty && pendingJobs.isEmpty {
      isProcessing = false
    }
    startProcessingIfNeeded()
  }

  /// Turns a thrown transcription error into a user-facing message with a
  /// recovery hint. Network errors are the common opaque case (especially for
  /// the Yap server path), so they get engine-specific guidance; everything
  /// else falls back to the error's own LocalizedError description, which our
  /// thrown NSErrors and YapError already populate with actionable text.
  static func describeFailure(_ error: Error, engine: TranscriptEngine) -> String {
    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet, .networkConnectionLost:
        return "No internet connection. Reconnect and retry."
      case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
        return engine == .yapServer
          ? "Can't reach the Yap server. Make sure it's running and the URL is correct in Settings › Transcript › Yap Server."
          : "Can't reach the server. Check your connection and retry."
      case .timedOut:
        return "The request timed out. Retry — the server may be busy or the audio is long."
      case .cancelled:
        return "The request was cancelled."
      default:
        return "Network error: \(urlError.localizedDescription)"
      }
    }
    return error.localizedDescription
  }

  // MARK: - Yap auto-transcript helpers

  /// Returns `true` when the podcast has not hit the consecutive-failure cap for
  /// automatic yap transcript queuing. Manual queuing is always allowed.
  func canAutoQueueYap(podcastTitle: String) -> Bool {
    (yapConsecutiveFailures[podcastTitle] ?? 0) < yapFailureLimit
  }

  private func setYapProgress(jobID: String, progress: Double) {
    // Monotonic guard: never let a late-arriving callback regress progress.
    guard case .transcribing(let current) = activeJobs[jobID]?.status,
          progress > current else { return }
    // Throttle: forward progress at most every 0.25s unless it jumps ≥5% or hits 100%.
    // Without this, YAP's poll loop fires several updates per second and every
    // @Observable consumer of activeJobs re-renders on each tick.
    let now = Date()
    let last = lastYapProgressUpdate[jobID] ?? .distantPast
    let elapsed = now.timeIntervalSince(last)
    let delta = progress - current
    guard elapsed >= 0.25 || delta >= 0.05 || progress >= 1.0 else { return }
    lastYapProgressUpdate[jobID] = now
    activeJobs[jobID]?.status = .transcribing(progress: progress)
  }

  /// Sends DELETE /transcriptions/{id} to the yap server for a given server job ID.
  private func cancelYapServerJob(serverJobID: String) {
    let serverURL = YapServerSettings.shared.serverURL
    let apiKey = YapServerSettings.shared.apiKey
    guard !serverURL.isEmpty, let base = URL(string: serverURL) else { return }
    Task {
      let service = YapTranscriptService()
      await service.cancelJob(serverJobID: serverJobID, baseURL: base, apiKey: apiKey.isEmpty ? nil : apiKey)
    }
  }
}
