//
//  ExpandedPlayerViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for expanded player view - supports Apple Podcasts style UI
//

import SwiftUI
import Observation
import SwiftData
import OSLog

#if os(iOS)
import UIKit
#else
import AppKit
#endif

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "ExpandedPlayerViewModel")

@MainActor
@Observable
final class ExpandedPlayerViewModel {
  // Stored properties that require SwiftData lookups
  var isStarred: Bool = false
  var isCompleted: Bool = false
  var podcastModel: PodcastInfoModel?

  // Transcript properties (loaded from disk)
  var hasTranscript: Bool = false
  var transcriptSegments: [TranscriptSegment] = []
  var transcriptSearchQuery: String = ""

  /// Sentence grouping cached at load time so `FullTranscriptContent` doesn't
  /// regroup on every body render. Recomputed in `loadTranscript` whenever
  /// `transcriptSegments` is reassigned.
  var groupedSentences: [TranscriptSentence] = []

  // Observable singletons — NOT @ObservationIgnored so SwiftUI can observe through them
  private let audioManager = EnhancedAudioManager.shared
  private let downloadManager = DownloadManager.shared
  private let subtitleSettings = SubtitleSettingsManager.shared

  @ObservationIgnored
  private let applePodcastService = ApplePodcastService()

  @ObservationIgnored
  private var shareTask: Task<Void, Never>?

  @ObservationIgnored
  private var loadTranscriptTask: Task<Void, Never>?

  @ObservationIgnored
  private var modelContext: ModelContext?

  @ObservationIgnored
  private var lastLoadedEpisodeId: String?

  @ObservationIgnored
  private var lastObservedEpisodeId: String?

  // Use Unit Separator (U+001F) as delimiter - same as DownloadManager
  private static let episodeKeyDelimiter = "\u{1F}"

  // MARK: - Computed Properties (delegating to @Observable singletons)

  var isPlaying: Bool { audioManager.isPlaying }
  var currentEpisode: PlaybackEpisode? { audioManager.currentEpisode }
  var episodeTitle: String { audioManager.currentEpisode?.title ?? "" }
  var podcastTitle: String { audioManager.currentEpisode?.podcastTitle ?? "" }
  var currentTime: TimeInterval { audioManager.currentTime }
  var duration: TimeInterval { audioManager.duration > 0 ? audioManager.duration : 1 }
  var playbackSpeed: Float { audioManager.playbackRate }
  var sleepTimerOption: SleepTimerOption { audioManager.sleepTimerOption }
  var sleepTimerRemaining: TimeInterval { audioManager.sleepTimerRemaining }
  var queue: [PlaybackEpisode] { audioManager.queue }
  var displayMode: SubtitleDisplayMode { subtitleSettings.displayMode }

  var imageURL: URL? {
    guard let urlString = audioManager.currentEpisode?.imageURL else { return nil }
    return URL(string: urlString)
  }

  var episodeDate: Date? { audioManager.currentEpisode?.pubDate }
  var episodeDescription: String? { audioManager.currentEpisode?.episodeDescription }

  var progress: Double {
    guard audioManager.duration > 0 else { return 0 }
    return audioManager.currentTime / audioManager.duration
  }

  var downloadState: DownloadState {
    guard let episode = audioManager.currentEpisode else { return .notDownloaded }
    return downloadManager.getDownloadState(
      episodeTitle: episode.title,
      podcastTitle: episode.podcastTitle
    )
  }

  init() {
    // Load episode-specific state on init
    checkEpisodeChange()
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    checkEpisodeChange()
  }

  /// Check if the current episode changed and reload stored state if needed.
  /// Called from setModelContext and can be called from view's onChange.
  func checkEpisodeChange() {
    let currentId = audioManager.currentEpisode?.id
    guard currentId != lastObservedEpisodeId else { return }
    lastObservedEpisodeId = currentId
    loadEpisodeState()
    loadPodcastModel()
    loadTranscript()
  }

  // MARK: - SwiftData Loading

  private func loadEpisodeState() {
    guard let context = modelContext, let episode = audioManager.currentEpisode else { return }

    let episodeKey = "\(episode.podcastTitle)\(Self.episodeKeyDelimiter)\(episode.title)"

    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == episodeKey }
    )

    do {
      if let model = try context.fetch(descriptor).first {
        isStarred = model.isStarred
        isCompleted = model.isCompleted
      } else {
        isStarred = false
        isCompleted = false
      }
    } catch {
      logger.error("Failed to load episode state: \(error.localizedDescription, privacy: .public)")
    }
  }

  func loadPodcastModel() {
    guard let context = modelContext else { return }

    let podcastName = podcastTitle
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.title == podcastName }
    )

    do {
      podcastModel = try context.fetch(descriptor).first
    } catch {
      logger.error("Failed to load podcast model: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func getOrCreateEpisodeModel() -> EpisodeDownloadModel? {
    guard let context = modelContext, let episode = audioManager.currentEpisode else { return nil }

    let episodeKey = "\(episode.podcastTitle)\(Self.episodeKeyDelimiter)\(episode.title)"

    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == episodeKey }
    )

    do {
      if let existing = try context.fetch(descriptor).first {
        return existing
      } else {
        // Create new model
        let model = EpisodeDownloadModel(
          episodeTitle: episode.title,
          podcastTitle: episode.podcastTitle,
          audioURL: episode.audioURL,
          imageURL: episode.imageURL,
          pubDate: episode.pubDate
        )
        context.insert(model)
        try context.save()
        return model
      }
    } catch {
      logger.error("Failed to get/create episode model: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  // MARK: - Computed Properties

  /// Whether duration is still loading (not yet available from player)
  var isDurationLoading: Bool {
    duration <= 0
  }

  var currentTimeString: String {
    formatTime(currentTime)
  }

  var remainingTimeString: String {
    guard duration > 0 else { return "--:--" }
    let remaining = duration - currentTime
    return "-" + formatTime(remaining)
  }

  var durationString: String {
    guard duration > 0 else { return "--:--" }
    return formatTime(duration)
  }

  // MARK: - Playback Actions

  func togglePlayPause() {
    if isPlaying {
      audioManager.pause()
    } else {
      audioManager.resume()
    }
  }

  func skipForward() {
    audioManager.skipForward()
  }

  func skipBackward() {
    audioManager.skipBackward()
  }

  func seekToProgress(_ progress: Double) {
    let newTime = progress * duration
    audioManager.seek(to: newTime)
  }

  func setPlaybackSpeed(_ speed: Float) {
    audioManager.setPlaybackRate(speed)
  }

  // MARK: - Episode Actions

  func toggleStar() {
    isStarred.toggle()

    // Persist to SwiftData
    guard let model = getOrCreateEpisodeModel() else { return }
    model.isStarred = isStarred
    try? modelContext?.save()
  }

  func togglePlayed() {
    isCompleted.toggle()

    // Persist to SwiftData
    guard let model = getOrCreateEpisodeModel() else { return }
    model.isCompleted = isCompleted
    if !isCompleted {
      model.lastPlaybackPosition = 0
    }
    try? modelContext?.save()
  }

  // MARK: - Sleep Timer

  func setSleepTimer(_ option: SleepTimerOption) {
    audioManager.setSleepTimer(option)
  }

  var isSleepTimerActive: Bool {
    audioManager.isSleepTimerActive
  }

  var sleepTimerRemainingFormatted: String {
    audioManager.sleepTimerRemainingFormatted
  }

  func shareEpisode() {
    guard let episode = audioManager.currentEpisode else { return }

    // Cancel previous share task
    shareTask?.cancel()

    // Try to find Apple Podcast URL first with timeout
    shareTask = Task {
      do {
        let appleUrl = try await withTimeout(seconds: 5) {
          try await self.applePodcastService.getAppleEpisodeLink(
            episodeTitle: episode.title,
            episodeGuid: episode.guid
          )
        }
        if !Task.isCancelled {
          shareWithURL(appleUrl ?? episode.audioURL)
        }
      } catch {
        if !Task.isCancelled {
          // On error, fall back to audio URL
          shareWithURL(episode.audioURL)
        }
      }
    }
  }

  private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask {
        try await operation()
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw CancellationError()
      }
      let result = try await group.next()!
      group.cancelAll()
      return result
    }
  }

  private func shareWithURL(_ urlString: String?) {
    guard let urlString = urlString, let url = URL(string: urlString) else { return }
    PlatformShareSheet.share(url: url)
  }

  func playNextCurrentEpisode() {
    guard let episode = audioManager.currentEpisode else { return }
    audioManager.playNext(episode)
  }

  // MARK: - Download Actions

  var hasLocalAudio: Bool {
    if case .downloaded = downloadState { return true }
    return false
  }

  var audioURL: String? {
    audioManager.currentEpisode?.audioURL
  }

  func startDownload() {
    guard let episode = audioManager.currentEpisode else { return }
    // Create a PodcastEpisodeInfo to pass to download manager
    let episodeInfo = PodcastEpisodeInfo(
      title: episode.title,
      podcastEpisodeDescription: episode.episodeDescription,
      pubDate: episode.pubDate,
      audioURL: episode.audioURL,
      imageURL: episode.imageURL,
      duration: episode.duration,
      guid: episode.guid
    )
    downloadManager.downloadEpisode(
      episode: episodeInfo,
      podcastTitle: episode.podcastTitle,
      language: "en"  // Default language
    )
  }

  func cancelDownload() {
    guard let episode = audioManager.currentEpisode else { return }
    downloadManager.cancelDownload(
      episodeTitle: episode.title,
      podcastTitle: episode.podcastTitle
    )
  }

  func deleteDownload() {
    guard let episode = audioManager.currentEpisode else { return }
    downloadManager.deleteDownload(
      episodeTitle: episode.title,
      podcastTitle: episode.podcastTitle
    )
  }

  // MARK: - Queue Actions

  func skipToQueueItem(at index: Int) {
    audioManager.skipToQueueItem(at: index)
  }

  func removeFromQueue(at index: Int) {
    audioManager.removeFromQueue(at: index)
  }

  func moveInQueue(from source: IndexSet, to destination: Int) {
    audioManager.moveInQueue(from: source, to: destination)
  }

  // MARK: - Transcript

  /// Current segment based on playback time
  var currentSegmentId: Int? {
    let time = currentTime
    return transcriptSegments.first { segment in
      time >= segment.startTime && time <= segment.endTime
    }?.id
  }

  /// Current segment text for display
  var currentSegmentText: String? {
    guard let id = currentSegmentId else { return nil }
    return transcriptSegments.first { $0.id == id }?.text
  }

  /// Filtered segments based on search query
  var filteredTranscriptSegments: [TranscriptSegment] {
    guard !transcriptSearchQuery.isEmpty else {
      return transcriptSegments
    }
    let query = transcriptSearchQuery
    return transcriptSegments.filter { segment in
      segment.text.localizedStandardContains(query)
    }
  }

  private func loadTranscript() {
    guard let episode = audioManager.currentEpisode else {
      hasTranscript = false
      transcriptSegments = []
      groupedSentences = []
      return
    }

    // Avoid reloading if already loaded for this episode
    let episodeId = episode.id
    if lastLoadedEpisodeId == episodeId && !transcriptSegments.isEmpty {
      return
    }

    loadTranscriptTask?.cancel()
    loadTranscriptTask = Task {
      if let segments = TranscriptStore.shared.loadSegments(
        episodeTitle: episode.title, podcastTitle: episode.podcastTitle
      ) {
        self.hasTranscript = true
        self.transcriptSegments = segments
        self.groupedSentences = TranscriptGrouping.groupIntoSentences(segments)
        self.lastLoadedEpisodeId = episodeId
      } else {
        self.hasTranscript = false
        self.transcriptSegments = []
        self.groupedSentences = []
      }
    }
  }

  /// Seek to a specific transcript segment
  func seekToSegment(_ segment: TranscriptSegment) {
    audioManager.seek(to: segment.startTime)
    if !isPlaying {
      audioManager.resume()
    }
  }

  // MARK: - Helpers

  private func formatTime(_ time: TimeInterval) -> String {
    guard time.isFinite && time >= 0 else { return "0:00" }

    let hours = Int(time) / 3600
    let minutes = Int(time) / 60 % 60
    let seconds = Int(time) % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }

  /// Clean up resources. Call this from onDisappear.
  func cleanup() {
    shareTask?.cancel()
    shareTask = nil
    loadTranscriptTask?.cancel()
    loadTranscriptTask = nil
  }
}
