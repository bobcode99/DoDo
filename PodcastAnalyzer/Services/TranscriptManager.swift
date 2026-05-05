//
//  TranscriptManager.swift
//  PodcastAnalyzer
//
//  Manages background transcript generation across the app
//

import Foundation
import Speech
import SwiftData
import OSLog

/// Tracks the status of a transcript generation job
enum TranscriptJobStatus: Equatable {
  case queued
  case downloadingModel(progress: Double)
  case transcribing(progress: Double)
  case completed
  case failed(error: String)
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

  // Use Unit Separator (U+001F) as delimiter - same as DownloadManager for consistency
  private static let episodeKeyDelimiter = "\u{1F}"

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranscriptManager")
  private let fileStorage = FileStorageManager.shared

  // Helper to create job ID matching episode key format
  private func makeJobId(podcastTitle: String, episodeTitle: String) -> String {
    return "\(podcastTitle)\(Self.episodeKeyDelimiter)\(episodeTitle)"
  }

  var activeJobs: [String: TranscriptJob] = [:]
  var isProcessing: Bool = false

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

        let transcriptService = TranscriptService(language: job.language ?? "en-us")

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

        var finalSRTContent: String?
        var lastUIUpdate = Date.distantPast
        for try await progressUpdate in await transcriptService.audioToSRTChunkedWithProgress(
          inputFile: audioURL)
        {
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
            audioURL: audioURL, locale: job.language, baseURL: base, apiKey: key)
        } else if let remoteURLString = job.audioRemoteURL, !remoteURLString.isEmpty {
          yapJobID = try await yapService.submitRemoteURLJob(
            remoteURL: remoteURLString, locale: job.language, baseURL: base, apiKey: key)
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
      logger.error("Transcript failed for \(job.episodeTitle): \(error.localizedDescription)")
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
