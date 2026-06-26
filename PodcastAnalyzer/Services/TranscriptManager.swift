//
//  TranscriptManager.swift
//  PodcastAnalyzer
//
//  Manages background transcript generation across the app
//

import SwiftData
import Foundation
import OSLog
import Speech

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

  /// Checks if a transcript is being generated for an episode
  func isGenerating(episodeTitle: String, podcastTitle: String) -> Bool {
    let jobId = makeJobId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)

    if pendingJobs.contains(where: { $0.id == jobId }) || runningJobIds.contains(jobId) {
      return true
    }

    if let job = activeJobs[jobId] {
      switch job.status {
      case .queued, .downloadingModel, .transcribing:
        return true
      case .completed, .failed:
        return false
      }
    }
    return false
  }

  /// Gets the current status of a transcript job
  func getJobStatus(episodeTitle: String, podcastTitle: String) -> TranscriptJobStatus? {
    let jobId = makeJobId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
    return activeJobs[jobId]?.status
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
            userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission denied. Enable in Settings > Privacy > Speech Recognition."]
          )
        case .restricted:
          throw NSError(
            domain: "TranscriptManager", code: 6,
            userInfo: [NSLocalizedDescriptionKey: "Speech recognition is restricted on this device."]
          )
        case .notDetermined:
          // Request permission
          let granted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
              continuation.resume(returning: status == .authorized)
            }
          }
          if !granted {
            throw NSError(
              domain: "TranscriptManager", code: 5,
              userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission denied. Enable in Settings > Privacy > Speech Recognition."]
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

        // Single-pass when the user turned off splitting; otherwise chunked
        // parallel parts (which itself falls back to single-pass under 1 min).
        let splitLongAudio = SubtitleSettingsManager.shared.splitLongAudio
        let progressStream = splitLongAudio
          ? await transcriptService.audioToSRTChunkedWithProgress(inputFile: audioURL)
          : await transcriptService.audioToSRTWithProgress(inputFile: audioURL)

        var finalSRTContent: String?
        var lastUIUpdate = Date.distantPast
        for try await progressUpdate in progressStream {
          let parts = progressUpdate.totalParts > 1
            ? TranscriptPartProgress(
                completed: progressUpdate.completedParts, total: progressUpdate.totalParts)
            : nil
          if progressUpdate.isComplete {
            finalSRTContent = progressUpdate.srtContent
            activeJobs[job.id]?.partProgress = parts
            activeJobs[job.id]?.status = .transcribing(progress: 1.0)
          } else {
            let now = Date()
            if now.timeIntervalSince(lastUIUpdate) >= 0.25 {
              activeJobs[job.id]?.partProgress = parts
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

        let whisperService = WhisperTranscriptService()
        var finalSRTContent: String?
        var lastUIUpdate = Date.distantPast

        for try await progressUpdate in await whisperService.audioToSRTWithProgress(
          inputFile: audioURL,
          modelVariant: modelVariant,
          language: job.language)
        {
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

        let srtContent = try await yapService.pollForResult(
          jobID: yapJobID, baseURL: base, apiKey: key, onProgress: onProgress
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
      activeJobs[job.id]?.status = .failed(error: error.localizedDescription)
      logger.error("Transcript failed for \(job.episodeTitle): \(error.localizedDescription, privacy: .public)")
      // Track consecutive yap failures to gate auto-queuing.
      let engine = job.engine ?? TranscriptEngine(
        rawValue: UserDefaults.standard.string(forKey: "transcriptEngine") ?? ""
      ) ?? .appleSpeech
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

  /// Stores the yap HTTP server job ID so it can be cancelled later.
  private func storeYapServerJobID(_ yapJobID: String, forJobID jobID: String) {
    activeJobs[jobID]?.yapServerJobID = yapJobID
    logger.info("[YapServer] tracked server job id=\(yapJobID) for episode job=\(jobID)")
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
