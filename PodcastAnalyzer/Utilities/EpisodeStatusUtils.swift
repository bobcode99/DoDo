//
//  EpisodeStatusUtils.swift
//  PodcastAnalyzer
//
//  Centralized utilities for checking episode status (downloaded, transcript, AI analysis, etc.)
//

import SwiftUI
import Foundation
import Observation
import SwiftData

// MARK: - Episode Key Utilities

nonisolated enum EpisodeKeyUtils {
  /// Unit Separator (U+001F) used as delimiter between podcast title and episode title
  static let delimiter = "\u{1F}"

  /// Create an episode key from podcast and episode titles
  static func makeKey(podcastTitle: String, episodeTitle: String) -> String {
    "\(podcastTitle)\(delimiter)\(episodeTitle)"
  }

  /// Parse an episode key into podcast and episode titles
  /// Supports both new format (Unit Separator) and old format (|) for backward compatibility
  static func parseKey(_ episodeKey: String) -> (podcastTitle: String, episodeTitle: String)? {
    // Try new format first (Unit Separator)
    if let delimiterIndex = episodeKey.range(of: delimiter) {
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
}

// MARK: - Episode Status Checker

/// Utility struct for checking various episode statuses
struct EpisodeStatusChecker {
  let episodeTitle: String
  let podcastTitle: String
  let audioURL: String?

  private let downloadManager = DownloadManager.shared

  init(episodeTitle: String, podcastTitle: String, audioURL: String? = nil) {
    self.episodeTitle = episodeTitle
    self.podcastTitle = podcastTitle
    self.audioURL = audioURL
  }

  /// Initialize from a LibraryEpisode
  init(episode: LibraryEpisode) {
    self.episodeTitle = episode.episodeInfo.title
    self.podcastTitle = episode.podcastTitle
    self.audioURL = episode.episodeInfo.audioURL
  }

  /// Initialize from a PodcastEpisodeInfo
  init(episode: PodcastEpisodeInfo, podcastTitle: String) {
    self.episodeTitle = episode.title
    self.podcastTitle = podcastTitle
    self.audioURL = episode.audioURL
  }

  // MARK: - Download Status

  /// Get the current download state for this episode
  var downloadState: DownloadState {
    downloadManager.getDownloadState(
      episodeTitle: episodeTitle,
      podcastTitle: podcastTitle
    )
  }

  /// Check if episode is fully downloaded
  var isDownloaded: Bool {
    if case .downloaded = downloadState { return true }
    return false
  }

  /// Check if episode is currently downloading
  var isDownloading: Bool {
    if case .downloading = downloadState { return true }
    return false
  }

  /// Get download progress (0.0 to 1.0) if downloading
  var downloadProgress: Double? {
    if case .downloading(let progress) = downloadState {
      return progress
    }
    return nil
  }

  /// Get the local file path if downloaded
  var localAudioPath: String? {
    if case .downloaded(let path) = downloadState {
      return path
    }
    return nil
  }

  /// Get the playback URL (local file if downloaded, otherwise remote URL)
  var playbackURL: String {
    if let path = localAudioPath {
      return URL(fileURLWithPath: path).absoluteString
    }
    return audioURL ?? ""
  }

  // MARK: - Transcript Status

  /// Check if a transcript exists for this episode.
  @MainActor
  var hasTranscript: Bool {
    TranscriptStore.shared.exists(episodeTitle: episodeTitle, podcastTitle: podcastTitle)
  }

  // MARK: - AI Analysis Status

  /// Check if AI analysis exists for this episode (requires ModelContext)
  func hasAIAnalysis(in modelContext: ModelContext) -> Bool {
    guard let audioURL = audioURL else { return false }

    let descriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )

    guard let model = try? modelContext.fetch(descriptor).first else {
      return false
    }

    return model.hasAnalysis
      || (model.qaHistoryJSON != nil && !model.qaHistoryJSON!.isEmpty)
  }

  // MARK: - Episode Key

  /// Get the unique key for this episode
  var episodeKey: String {
    EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
  }
}

// MARK: - Episode Status Observer

/// Observable class that reactively tracks episode status changes
/// Observes DownloadManager and TranscriptManager for real-time updates
@MainActor
@Observable
final class EpisodeStatusObserver {
  // Status properties
  var downloadState: DownloadState = .notDownloaded
  var isDownloaded: Bool = false
  var isDownloading: Bool = false
  var downloadProgress: Double = 0
  var hasTranscript: Bool = false
  var isTranscribing: Bool = false
  var isDownloadingModel: Bool = false
  var transcriptProgress: Double = 0
  var hasAIAnalysis: Bool = false

  // Episode info
  @ObservationIgnored
  private let episodeTitle: String

  @ObservationIgnored
  private let podcastTitle: String

  @ObservationIgnored
  private let audioURL: String?

  @ObservationIgnored
  let episodeKey: String

  // Managers
  @ObservationIgnored
  private let downloadManager = DownloadManager.shared

  @ObservationIgnored
  private let transcriptManager = TranscriptManager.shared

  @ObservationIgnored
  private var modelContext: ModelContext?

  @ObservationIgnored
  private var isObserving = false

  @ObservationIgnored
  private var isCleaned = false

  init(episodeTitle: String, podcastTitle: String, audioURL: String? = nil) {
    self.episodeTitle = episodeTitle
    self.podcastTitle = podcastTitle
    self.audioURL = audioURL
    self.episodeKey = EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
    setupObservers()
    updateAllStatus()
  }

  convenience init(episode: LibraryEpisode) {
    self.init(
      episodeTitle: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle,
      audioURL: episode.episodeInfo.audioURL
    )
  }

  convenience init(episode: PodcastEpisodeInfo, podcastTitle: String) {
    self.init(
      episodeTitle: episode.title,
      podcastTitle: podcastTitle,
      audioURL: episode.audioURL
    )
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    checkAIAnalysis()
  }

  private func setupObservers() {
    guard !isObserving else { return }
    isObserving = true
    observeDownloadManager()
    observeTranscriptManager()
  }

  private func observeDownloadManager() {
    // Don't start observation if already cleaned up
    guard !isCleaned else { return }

    withObservationTracking {
      // Access the property to register observation
      _ = downloadManager.downloadStates
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self, !self.isCleaned else { return }
        // Fast-path: only run the expensive updateDownloadStatus (which does
        // synchronous disk I/O) when THIS episode's state actually changed.
        // Without this guard every progress tick for ANY download triggers
        // disk checks for ALL visible episodes.
        if self.stateChangedForThisEpisode() {
          self.updateDownloadStatus()
        }
        self.observeDownloadManager()
      }
    }
  }

  /// Cheap check — returns true when the download state for this specific
  /// episode differs from the last value we stored.
  /// Reads inFlightProgress (non-observable) for progress comparison to
  /// avoid creating additional @Observable subscriptions on progress ticks.
  private func stateChangedForThisEpisode() -> Bool {
    // Check non-observable progress first for actively downloading episodes
    if case .downloading = downloadState,
       let newP = downloadManager.inFlightProgress[episodeKey] {
      return abs(newP - downloadProgress) >= 0.01
    }
    let dictState = downloadManager.downloadStates[episodeKey]
    switch (dictState, downloadState) {
    case (nil, .notDownloaded):
      return false
    case (.downloading, .downloading):
      // Progress comparison already handled above via inFlightProgress
      return false
    case let (new?, old) where new == old:
      return false
    default:
      return true
    }
  }

  private func observeTranscriptManager() {
    // Don't start observation if already cleaned up
    guard !isCleaned else { return }

    withObservationTracking {
      // Access properties to register observation
      _ = transcriptManager.activeJobs
      _ = transcriptManager.isProcessing
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self, !self.isCleaned else { return }
        self.updateTranscriptStatus()
        self.observeTranscriptManager()
      }
    }
  }

  func updateAllStatus() {
    updateDownloadStatus()
    updateTranscriptStatus()
    checkAIAnalysis()
  }

  private func updateDownloadStatus() {
    let state = downloadManager.getDownloadState(
      episodeTitle: episodeTitle,
      podcastTitle: podcastTitle
    )
    let previousState = downloadState
    downloadState = state

    switch state {
    case .downloaded:
      isDownloaded = true
      isDownloading = false
      downloadProgress = 1.0
    case .downloading(let progress):
      isDownloaded = false
      isDownloading = true
      downloadProgress = progress
    case .finishing:
      isDownloaded = false
      isDownloading = true
      downloadProgress = 1.0
    case .failed:
      isDownloaded = false
      isDownloading = false
      downloadProgress = 0
    case .notDownloaded:
      isDownloaded = false
      isDownloading = false
      downloadProgress = 0
    }

    // Only check transcript status when transitioning into .downloaded — the transcript file
    // cannot appear or disappear during a progress tick, and hasTranscript does synchronous
    // disk I/O that blocks @MainActor unnecessarily on every throttled progress update.
    if case .downloaded = state {
      if case .downloaded = previousState {
        // Already was downloaded — no transition, skip disk I/O
      } else {
        updateTranscriptStatus()
      }
    }
  }

  private func updateTranscriptStatus() {
    // Check if transcript file exists
    let checker = EpisodeStatusChecker(
      episodeTitle: episodeTitle,
      podcastTitle: podcastTitle,
      audioURL: audioURL
    )
    hasTranscript = checker.hasTranscript

    // Check if transcript is currently being generated
    if let job = transcriptManager.activeJobs[episodeKey] {
      isTranscribing = true
      // Extract progress from job status
      switch job.status {
      case .transcribing(let progress):
        isDownloadingModel = false
        transcriptProgress = progress
      case .downloadingModel(let progress):
        isDownloadingModel = true
        transcriptProgress = progress
      case .queued:
        isDownloadingModel = false
        transcriptProgress = 0
      case .completed:
        isDownloadingModel = false
        transcriptProgress = 1.0
        isTranscribing = false
        hasTranscript = true
      case .failed:
        isDownloadingModel = false
        transcriptProgress = 0
        isTranscribing = false
      }
    } else {
      isTranscribing = false
      isDownloadingModel = false
      transcriptProgress = hasTranscript ? 1.0 : 0
    }
  }

  func checkAIAnalysis() {
    guard let context = modelContext, let audioURL = audioURL else {
      hasAIAnalysis = false
      return
    }

    let descriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate { $0.episodeAudioURL == audioURL }
    )

    guard let model = try? context.fetch(descriptor).first else {
      hasAIAnalysis = false
      return
    }

    hasAIAnalysis = model.hasAnalysis
      || (model.qaHistoryJSON != nil && !model.qaHistoryJSON!.isEmpty)
  }

  var playbackURL: String {
    if case .downloaded(let path) = downloadState {
      return URL(fileURLWithPath: path).absoluteString
    }
    return audioURL ?? ""
  }

  func cleanup() {
    isCleaned = true
    isObserving = false
  }
}
