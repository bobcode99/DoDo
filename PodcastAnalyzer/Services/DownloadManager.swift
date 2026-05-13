//
//  DownloadState.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

//
//  DownloadManager.swift
//  PodcastAnalyzer
//
//  Manages episode downloads with progress tracking
//

import Foundation
import Observation
import OSLog
import SwiftData

#if DEBUG
private let signpostLog = OSLog(subsystem: "com.podcast.analyzer", category: "PointsOfInterest")
#endif

enum DownloadState: Codable, Equatable, Sendable {
  case notDownloaded
  case downloading(progress: Double)
  case finishing  // Download complete, processing file
  case downloaded(localPath: String)
  case failed(error: String)
}

// MARK: - Download Session Delegate

/// Handles URLSession delegate callbacks on background threads
/// Communicates with DownloadManager via async/await
private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, Sendable {

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "DownloadDelegate")

  // Thread-safe storage for tracking downloads (accessed from URLSession background queue)
  private let downloadTracker = DownloadTracker()

  // Actor for thread-safe download tracking
  private actor DownloadTracker {
    var activeDownloads: [String: URLSessionDownloadTask] = [:]
    var originalURLs: [String: URL] = [:]
    var episodeLanguages: [String: String] = [:]
    var transcriptURLs: [String: String] = [:]
    var transcriptTypes: [String: String] = [:]

    // Throttle state: suppress MainActor progress updates that are too frequent
    private var lastProgressUpdate: [String: (time: Date, progress: Double)] = [:]

    /// Returns true only when enough time has passed (≥250 ms) or progress jumped ≥5%.
    /// Call this before dispatching to MainActor to avoid flooding the UI.
    func shouldUpdateProgress(for key: String, newProgress: Double) -> Bool {
      let now = Date()
      if let last = lastProgressUpdate[key] {
        let elapsed = now.timeIntervalSince(last.time)
        let delta = abs(newProgress - last.progress)
        guard elapsed >= 0.25 || delta >= 0.05 else { return false }
      }
      lastProgressUpdate[key] = (now, newProgress)
      return true
    }

    func setDownload(
      _ task: URLSessionDownloadTask,
      for key: String,
      originalURL: URL,
      language: String,
      transcriptURL: String? = nil,
      transcriptType: String? = nil
    ) {
      activeDownloads[key] = task
      originalURLs[key] = originalURL
      episodeLanguages[key] = language
      if let url = transcriptURL {
        transcriptURLs[key] = url
      }
      if let type = transcriptType {
        transcriptTypes[key] = type
      }
    }

    func getDownloadKey(for task: URLSessionTask) -> String? {
      activeDownloads.first(where: { $0.value === task })?.key
    }

    func getOriginalURL(for key: String) -> URL? {
      originalURLs[key]
    }

    func getLanguage(for key: String) -> String {
      episodeLanguages[key] ?? "en"
    }

    func getTranscriptInfo(for key: String) -> (url: String, type: String)? {
      guard let url = transcriptURLs[key], let type = transcriptTypes[key] else {
        return nil
      }
      return (url, type)
    }

    func removeDownload(for key: String) {
      activeDownloads.removeValue(forKey: key)
      originalURLs.removeValue(forKey: key)
      episodeLanguages.removeValue(forKey: key)
      transcriptURLs.removeValue(forKey: key)
      transcriptTypes.removeValue(forKey: key)
      lastProgressUpdate.removeValue(forKey: key)
    }

    func cancelDownload(for key: String) -> URLSessionDownloadTask? {
      guard let task = activeDownloads[key] else { return nil }
      activeDownloads.removeValue(forKey: key)
      originalURLs.removeValue(forKey: key)
      episodeLanguages.removeValue(forKey: key)
      transcriptURLs.removeValue(forKey: key)
      transcriptTypes.removeValue(forKey: key)
      lastProgressUpdate.removeValue(forKey: key)
      return task
    }
  }

  // Use Unit Separator (U+001F) as delimiter
  private static let episodeKeyDelimiter = "\u{1F}"

  func makeKey(episode: String, podcast: String) -> String {
    "\(podcast)\(Self.episodeKeyDelimiter)\(episode)"
  }

  private func parseEpisodeKey(_ episodeKey: String) -> (podcastTitle: String, episodeTitle: String)? {
    if let delimiterIndex = episodeKey.range(of: Self.episodeKeyDelimiter) {
      let podcastTitle = String(episodeKey[..<delimiterIndex.lowerBound])
      let episodeTitle = String(episodeKey[delimiterIndex.upperBound...])
      return (podcastTitle, episodeTitle)
    }

    // Fall back to old format (|) for backward compatibility
    if let lastPipeIndex = episodeKey.lastIndex(of: "|") {
      let podcastTitle = String(episodeKey[..<lastPipeIndex])
      let episodeTitle = String(episodeKey[episodeKey.index(after: lastPipeIndex)...])
      return (podcastTitle, episodeTitle)
    }

    return nil
  }

  // MARK: - Public Methods (called from DownloadManager)

  func startDownload(
    url: URL,
    episodeTitle: String,
    podcastTitle: String,
    language: String,
    transcriptURL: String? = nil,
    transcriptType: String? = nil,
    session: URLSession
  ) async -> URLSessionDownloadTask {
    let episodeKey = makeKey(episode: episodeTitle, podcast: podcastTitle)

    // Cancel existing download if any
    if let existingTask = await downloadTracker.cancelDownload(for: episodeKey) {
      existingTask.cancel()
    }

    let task = session.downloadTask(with: url)
    await downloadTracker.setDownload(
      task,
      for: episodeKey,
      originalURL: url,
      language: language,
      transcriptURL: transcriptURL,
      transcriptType: transcriptType
    )
    return task
  }

  func cancelDownload(episodeTitle: String, podcastTitle: String) async {
    let episodeKey = makeKey(episode: episodeTitle, podcast: podcastTitle)
    if let task = await downloadTracker.cancelDownload(for: episodeKey) {
      task.cancel()
    }
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // CRITICAL: URLSession deletes the temp file as soon as this method returns!
    // We MUST copy the file SYNCHRONOUSLY here, before any async work.

    // Get file extension from URL
    let originalURL = downloadTask.originalRequest?.url
    var fileExtension = originalURL?.pathExtension.lowercased() ?? "mp3"
    let validExtensions = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]
    if fileExtension.isEmpty || !validExtensions.contains(fileExtension) {
      fileExtension = "mp3"
    }

    // Create our own temp file and copy SYNCHRONOUSLY
    let tempDirectory = FileManager.default.temporaryDirectory
    let ourTempFile = tempDirectory.appendingPathComponent(UUID().uuidString + ".\(fileExtension)")

    do {
      try FileManager.default.copyItem(at: location, to: ourTempFile)
      logger.info("Copied download to temp location: \(ourTempFile.lastPathComponent)")
    } catch {
      logger.error("Failed to copy temp file: \(error.localizedDescription)")
      // Update state asynchronously
      Task {
        if let episodeKey = await downloadTracker.getDownloadKey(for: downloadTask) {
          await downloadTracker.removeDownload(for: episodeKey)
          await MainActor.run {
            DownloadManager.shared.inFlightProgress.removeValue(forKey: episodeKey)
            DownloadManager.shared.downloadStates[episodeKey] = .failed(error: "Failed to save download: \(error.localizedDescription)")
          }
        }
      }
      return
    }

    // Now do the rest asynchronously - the file is safely copied
    Task {
      guard let episodeKey = await downloadTracker.getDownloadKey(for: downloadTask) else {
        logger.warning("Download finished but no matching episode key found")
        try? FileManager.default.removeItem(at: ourTempFile)
        return
      }

      guard let (podcastTitle, episodeTitle) = parseEpisodeKey(episodeKey) else {
        logger.error("Invalid episode key format: \(episodeKey)")
        try? FileManager.default.removeItem(at: ourTempFile)
        return
      }

      logger.info("Download finished for: \(episodeTitle), processing file...")

      do {
        logger.info("Processing downloaded file for: \(episodeTitle)")

        // Set finishing state on main thread
        await MainActor.run {
          DownloadManager.shared.inFlightProgress.removeValue(forKey: episodeKey)
          DownloadManager.shared.downloadStates[episodeKey] = .finishing
        }

        // Move to final destination
        let fileStorage = FileStorageManager.shared
        let destinationURL = try await fileStorage.saveAudioFile(
          from: ourTempFile,
          episodeTitle: episodeTitle,
          podcastTitle: podcastTitle
        )

        // Clean up temp file
        try? FileManager.default.removeItem(at: ourTempFile)

        // Get language for auto-transcript
        let language = await downloadTracker.getLanguage(for: episodeKey)

        // Get transcript info for auto-download
        let transcriptInfo = await downloadTracker.getTranscriptInfo(for: episodeKey)

        // Remove from tracker
        await downloadTracker.removeDownload(for: episodeKey)

        // Update state on MainActor
        await MainActor.run {
          let manager = DownloadManager.shared
          manager.inFlightProgress.removeValue(forKey: episodeKey)
          manager.downloadStates[episodeKey] = .downloaded(localPath: destinationURL.path)

          // AntennaPod pattern: disable per-episode auto-download after successful download
          // so the coordinator never re-downloads the same episode automatically.
          if let container = DownloadManager.shared.modelContainer {
            let ctx = ModelContext(container)
            let descriptor = FetchDescriptor<EpisodeDownloadModel>(
              predicate: #Predicate { $0.id == episodeKey }
            )
            if let epModel = try? ctx.fetch(descriptor).first {
              epModel.autoDownloadEnabled = false
              try? ctx.save()
            }
            // Remove from coordinator's pending list.
            Task { await AutoDownloadCoordinator.shared.removePending(podcastTitle: podcastTitle, episodeTitle: episodeTitle) }
          }

          // Post notification
          NotificationCenter.default.post(
            name: .episodeDownloadCompleted,
            object: nil,
            userInfo: [
              "episodeTitle": episodeTitle,
              "podcastTitle": podcastTitle,
              "localPath": destinationURL.path
            ]
          )

          // Trigger auto-transcript if enabled (global engine)
          if SubtitleSettingsManager.shared.autoGenerateTranscripts {
            TranscriptManager.shared.queueTranscript(
              episodeTitle: episodeTitle,
              podcastTitle: podcastTitle,
              audioPath: destinationURL.path,
              language: language
            )
          }

          // Per-podcast auto-transcribe: resolve engine at run time (YAP / local / skip).
          let container = DownloadManager.shared.modelContainer
          if let container {
            let ctx = ModelContext(container)
            let title = podcastTitle
            let descriptor = FetchDescriptor<PodcastInfoModel>(
              predicate: #Predicate { $0.title == title && $0.isSubscribed == true }
            )
            if let podcast = try? ctx.fetch(descriptor).first,
               podcast.autoTranscribeNewEpisodes,
               !TranscriptManager.shared.isGenerating(episodeTitle: episodeTitle, podcastTitle: podcastTitle),
               let engine = TranscriptManager.shared.engineForAutoEnqueue(podcastTitle: podcastTitle) {
              TranscriptManager.shared.queueTranscript(
                episodeTitle: episodeTitle,
                podcastTitle: podcastTitle,
                audioPath: destinationURL.path,
                audioRemoteURL: nil,
                language: language,
                engine: engine
              )
            }
          }
        }

        // Auto-download RSS transcript if enabled and available
        if let info = transcriptInfo,
           let url = URL(string: info.url) {
          let settings = await MainActor.run { SubtitleSettingsManager.shared }
          if await settings.autoDownloadTranscripts {
            do {
              _ = try await TranscriptDownloadService.shared.downloadTranscript(
                from: url,
                type: info.type,
                episodeTitle: episodeTitle,
                podcastTitle: podcastTitle
              )
              logger.info("Auto-downloaded RSS transcript for: \(episodeTitle)")
            } catch {
              logger.warning("Auto-download RSS transcript failed: \(error.localizedDescription)")
            }
          }
        }

        logger.info("Download completed successfully: \(episodeTitle)")

      } catch {
        try? FileManager.default.removeItem(at: ourTempFile)
        await downloadTracker.removeDownload(for: episodeKey)

        await MainActor.run {
          DownloadManager.shared.inFlightProgress.removeValue(forKey: episodeKey)
          DownloadManager.shared.downloadStates[episodeKey] = .failed(error: error.localizedDescription)
        }
        logger.error("Download save failed: \(error.localizedDescription)")
      }
    }
  }

  func urlSession(
    _ session: URLSession, downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }

    let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

    Task {
      guard let episodeKey = await downloadTracker.getDownloadKey(for: downloadTask) else { return }

      // Throttle: skip the MainActor dispatch when updates are too frequent.
      // URLSession fires this delegate for every received chunk (potentially
      // hundreds of times/sec), which would flood @Observable and cause UI lag.
      guard await downloadTracker.shouldUpdateProgress(for: episodeKey, newProgress: progress) else { return }

      await MainActor.run {
        let manager = DownloadManager.shared
        // Update non-observable progress storage only — avoids @Observable invalidation
        // that would trigger cascading view re-renders on every tick.
        if case .downloading = manager.downloadStates[episodeKey] {
          manager.inFlightProgress[episodeKey] = progress
        } else if manager.downloadStates[episodeKey] == nil {
          manager.inFlightProgress[episodeKey] = progress
        }
      }
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error = error else { return }

    // Ignore cancellation errors
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
      logger.info("Download was cancelled")
      return
    }

    Task {
      guard let episodeKey = await downloadTracker.getDownloadKey(for: task) else { return }
      await downloadTracker.removeDownload(for: episodeKey)

      await MainActor.run {
        DownloadManager.shared.inFlightProgress.removeValue(forKey: episodeKey)
        DownloadManager.shared.downloadStates[episodeKey] = .failed(error: error.localizedDescription)
      }
      logger.error("Download failed: \(error.localizedDescription)")
    }
  }
}

// MARK: - Download Manager

@MainActor
@Observable
final class DownloadManager {
  static let shared = DownloadManager()

  var downloadStates: [String: DownloadState] = [:]

  @ObservationIgnored
  private let sessionDelegate = DownloadSessionDelegate()

  @ObservationIgnored
  private lazy var urlSession: URLSession = {
    let config = URLSessionConfiguration.background(
      withIdentifier: "com.podcast.analyzer.downloads")
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    return URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
  }()

  @ObservationIgnored
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "DownloadManager")

  @ObservationIgnored
  private let fileStorage = FileStorageManager.shared

  @ObservationIgnored
  var modelContainer: ModelContainer?

  func setModelContainer(_ container: ModelContainer) {
    self.modelContainer = container
  }

  /// Episode keys whose on-disk presence has already been checked.
  /// Prevents `getDownloadState` from repeating 7-extension disk scans on every call.
  @ObservationIgnored
  private var diskCheckedKeys = Set<String>()

  /// Non-observable storage for in-flight download progress (0.0–1.0).
  /// Updated by URLSession delegate on every throttled tick without triggering
  /// @Observable invalidation. ViewModels poll this on a timer for smooth UI updates.
  @ObservationIgnored
  var inFlightProgress: [String: Double] = [:]

  /// True when at least one download is actively transferring data.
  /// ViewModels use this to start/stop their progress-polling timers.
  var hasActiveDownloads: Bool { !inFlightProgress.isEmpty }

  private init() {}

  // MARK: - State Restoration

  /// Synchronously checks if audio file exists on disk
  private func checkAudioFileExistsSynchronously(episodeTitle: String, podcastTitle: String) -> String? {
    let fm = FileManager.default

    #if os(macOS)
    let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let audioDir = appSupport.appendingPathComponent("PodcastAnalyzer/Audio", isDirectory: true)
    #else
    let libraryDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    let audioDir = libraryDir.appendingPathComponent("Audio", isDirectory: true)
    #endif

    let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
    let baseFileName = "\(podcastTitle)_\(episodeTitle)"
      .components(separatedBy: invalidCharacters)
      .joined(separator: "_")
      .trimmingCharacters(in: .whitespaces)

    let possibleExtensions = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]

    for ext in possibleExtensions {
      let path = audioDir.appendingPathComponent("\(baseFileName).\(ext)")
      if fm.fileExists(atPath: path.path) {
        return path.path
      }
    }
    return nil
  }

  // MARK: - Download Control

  func downloadEpisode(episode: PodcastEpisodeInfo, podcastTitle: String, language: String = "en") {
    let episodeKey = sessionDelegate.makeKey(episode: episode.title, podcast: podcastTitle)

    // Fast-path: skip if already in-flight or done
    switch downloadStates[episodeKey] {
    case .downloading, .finishing:
      logger.info("Download already in progress for: \(episode.title)")
      return
    case .downloaded:
      return
    default:
      break
    }

    guard let audioURLString = episode.audioURL,
          let url = URL(string: audioURLString)
    else {
      logger.error("Invalid audio URL for episode: \(episode.title)")
      downloadStates[episodeKey] = .failed(error: "Invalid URL")
      return
    }

    // Check if already downloaded
    Task {
      let exists = await fileStorage.audioFileExists(
        for: episode.title, podcastTitle: podcastTitle)
      if exists {
        let path = await fileStorage.audioFilePath(
          for: episode.title, podcastTitle: podcastTitle)
        downloadStates[episodeKey] = .downloaded(localPath: path.path)
        return
      }

      // Check available disk space before starting download (require at least 50 MB)
      do {
        let attrs = try FileManager.default.attributesOfFileSystem(
          forPath: NSHomeDirectory())
        if let freeSpace = attrs[.systemFreeSize] as? Int64,
           freeSpace < 50 * 1024 * 1024 {
          logger.warning("Insufficient disk space for download: \(freeSpace / 1_048_576) MB free")
          downloadStates[episodeKey] = .failed(error: "Not enough disk space (need at least 50 MB)")
          return
        }
      } catch {
        logger.warning("Could not check disk space: \(error.localizedDescription)")
        // Proceed anyway — disk space check is best-effort
      }

      // Start download
      downloadStates[episodeKey] = .downloading(progress: 0)
      inFlightProgress[episodeKey] = 0
      #if DEBUG
      os_signpost(.event, log: signpostLog, name: "DownloadManager.startDownload", "%{public}s", episode.title)
      #endif
      let task = await sessionDelegate.startDownload(
        url: url,
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        language: language,
        transcriptURL: episode.transcriptURL,
        transcriptType: episode.transcriptType,
        session: urlSession
      )
      task.resume()
      logger.info("Started download: \(episode.title)")
    }
  }

  func cancelDownload(episodeTitle: String, podcastTitle: String) {
    let episodeKey = sessionDelegate.makeKey(episode: episodeTitle, podcast: podcastTitle)

    Task {
      await sessionDelegate.cancelDownload(episodeTitle: episodeTitle, podcastTitle: podcastTitle)
      inFlightProgress.removeValue(forKey: episodeKey)
      downloadStates[episodeKey] = .notDownloaded
      logger.info("Cancelled download: \(episodeTitle)")
    }
  }

  func deleteDownload(episodeTitle: String, podcastTitle: String) {
    let episodeKey = sessionDelegate.makeKey(episode: episodeTitle, podcast: podcastTitle)

    Task {
      do {
        try await fileStorage.deleteAudioFile(for: episodeTitle, podcastTitle: podcastTitle)

        // Also delete captions if they exist
        if await fileStorage.captionFileExists(for: episodeTitle, podcastTitle: podcastTitle) {
          try await fileStorage.deleteCaptionFile(for: episodeTitle, podcastTitle: podcastTitle)
        }

        inFlightProgress.removeValue(forKey: episodeKey)
        downloadStates[episodeKey] = .notDownloaded
        // Reset disk-check cache so a future re-download can be discovered
        diskCheckedKeys.remove(episodeKey)
        logger.info("Deleted download: \(episodeTitle)")
      } catch {
        logger.error("Failed to delete download: \(error.localizedDescription)")
      }
    }
  }

  func getDownloadState(episodeTitle: String, podcastTitle: String) -> DownloadState {
    let episodeKey = sessionDelegate.makeKey(episode: episodeTitle, podcast: podcastTitle)

    // First-time disk check for this key (only once per key to avoid repeated I/O)
    if !diskCheckedKeys.contains(episodeKey) {
      diskCheckedKeys.insert(episodeKey)
      if let path = checkAudioFileExistsSynchronously(
        episodeTitle: episodeTitle, podcastTitle: podcastTitle)
      {
        Task { @MainActor [weak self] in
          self?.downloadStates[episodeKey] = .downloaded(localPath: path)
        }
        return .downloaded(localPath: path)
      }
    }

    // Always read downloadStates first to establish the @Observable subscription.
    // This ensures any view calling this method re-renders on state transitions
    // (start / finish / fail) even when inFlightProgress is non-nil.
    let persistedState = downloadStates[episodeKey]

    // Return in-flight progress from the non-observable store so progress ticks
    // don't trigger cascading view re-renders (see inFlightProgress comments above).
    if let progress = inFlightProgress[episodeKey] {
      return .downloading(progress: progress)
    }

    guard let state = persistedState else {
      return .notDownloaded
    }

    // If state says downloaded, verify the file still exists on disk
    if case .downloaded(let path) = state {
      if !FileManager.default.fileExists(atPath: path) {
        logger.warning("Download record exists but file missing on disk: \(path)")
        Task { @MainActor [weak self] in
          self?.downloadStates[episodeKey] = .notDownloaded
        }
        return .notDownloaded
      }
    }

    return state
  }

  func getLocalPath(episodeTitle: String, podcastTitle: String) -> String? {
    let state = getDownloadState(episodeTitle: episodeTitle, podcastTitle: podcastTitle)
    if case .downloaded(let path) = state {
      return path
    }
    return nil
  }
}
