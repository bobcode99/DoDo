//
//  LibraryViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for Library tab - manages subscribed podcasts, saved, downloaded, and latest episodes
//

import SwiftUI
import Foundation
import SwiftData
import OSLog

#if DEBUG
private let signpostLog = OSLog(subsystem: "com.podcast.analyzer", category: "PointsOfInterest")
#endif

// MARK: - Library Episode Model

struct LibraryEpisode: Identifiable, Hashable {
  static func == (lhs: LibraryEpisode, rhs: LibraryEpisode) -> Bool {
    lhs.id == rhs.id
  }
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  let id: String
  let podcastTitle: String
  let imageURL: String?
  let language: String
  let episodeInfo: PodcastEpisodeInfo
  let isStarred: Bool
  let isDownloaded: Bool
  let isCompleted: Bool
  let lastPlaybackPosition: TimeInterval
  /// Actual duration measured by AVPlayer and stored in SwiftData.
  /// More accurate than `episodeInfo.duration` which comes from potentially
  /// wrong RSS metadata. Zero means not yet measured.
  let savedDuration: TimeInterval

  var hasProgress: Bool {
    lastPlaybackPosition > 0 && !isCompleted
  }

  /// Progress percentage (0.0 to 1.0).
  /// Prefers `savedDuration` (measured by AVPlayer) over RSS metadata duration.
  var progress: Double {
    let dur: Double
    if savedDuration > 0 {
      dur = savedDuration
    } else if let rss = episodeInfo.duration, rss > 0 {
      dur = Double(rss)
    } else {
      return 0
    }
    return min(lastPlaybackPosition / dur, 1.0)
  }
}

// MARK: - Downloading Episode Model

struct DownloadingEpisode: Identifiable {
  let id: String
  let episodeTitle: String
  let podcastTitle: String
  let imageURL: String?
  let progress: Double
  let state: DownloadState
}

// MARK: - Downloaded Podcast Group Model

struct DownloadedPodcastGroup: Identifiable {
  let title: String
  let imageURL: String?
  let podcast: PodcastInfoModel?
  let downloadCount: Int

  var id: String {
    podcast?.id.uuidString ?? title
  }
}

// MARK: - Library ViewModel

@MainActor
@Observable
final class LibraryViewModel {
  var podcastInfoModelList: [PodcastInfoModel] = []
  var savedEpisodes: [LibraryEpisode] = []
  var downloadedEpisodes: [LibraryEpisode] = []
  var downloadingEpisodes: [DownloadingEpisode] = []
  var latestEpisodes: [LibraryEpisode] = []
  var isLoading = false
  var error: String?

  // Private DTO for background processing
  private struct EpisodeDownloadData: Sendable {
    let id: String
    let isStarred: Bool
    let localAudioPath: String?
    let isCompleted: Bool
    let lastPlaybackPosition: TimeInterval
    let duration: TimeInterval
  }

  /// Sendable snapshot of all EpisodeDownloadModel fields needed for background LibraryEpisode construction.
  private struct FullEpisodeSnapshot: Sendable {
    let id: String
    let podcastTitle: String
    let episodeTitle: String
    let audioURL: String?
    let imageURL: String?
    let pubDate: Date?
    let localAudioPath: String?
    let isStarred: Bool
    let isCompleted: Bool
    let lastPlaybackPosition: TimeInterval
    let duration: TimeInterval

    init(from model: EpisodeDownloadModel) {
      self.id = model.id
      self.podcastTitle = model.podcastTitle
      self.episodeTitle = model.episodeTitle
      self.audioURL = model.audioURL
      self.imageURL = model.imageURL
      self.pubDate = model.pubDate
      self.localAudioPath = model.localAudioPath
      self.isStarred = model.isStarred
      self.isCompleted = model.isCompleted
      self.lastPlaybackPosition = model.lastPlaybackPosition
      self.duration = model.duration
    }
  }


  // Simplified loading state
  // We only track generally if background operations are happening,
  // but we don't block the UI with specific flags for each section anymore.
  // The UI should show whatever data is available.
  var isRefreshing = false

  /// True once setModelContext has been called and the initial load has been kicked off.
  /// Views can use this to skip redundant refreshes on re-appearance.
  var isLoaded: Bool { isAlreadyLoaded }


  // Search state for subpages
  var savedSearchText: String = ""
  var downloadedSearchText: String = ""
  var latestSearchText: String = ""

  // Filtered arrays based on search text
  var filteredSavedEpisodes: [LibraryEpisode] {
    guard !savedSearchText.isEmpty else { return savedEpisodes }
    let query = savedSearchText
    return savedEpisodes.filter {
      $0.episodeInfo.title.localizedStandardContains(query) ||
      $0.podcastTitle.localizedStandardContains(query)
    }
  }

  var filteredDownloadedEpisodes: [LibraryEpisode] {
    guard !downloadedSearchText.isEmpty else { return downloadedEpisodes }
    let query = downloadedSearchText
    return downloadedEpisodes.filter {
      $0.episodeInfo.title.localizedStandardContains(query) ||
      $0.podcastTitle.localizedStandardContains(query)
    }
  }

  var filteredLatestEpisodes: [LibraryEpisode] {
    guard !latestSearchText.isEmpty else { return latestEpisodes }
    let query = latestSearchText
    return latestEpisodes.filter {
      $0.episodeInfo.title.localizedStandardContains(query) ||
      $0.podcastTitle.localizedStandardContains(query)
    }
  }

  /// Podcasts that have downloaded episodes, with download counts
  var podcastsWithDownloads: [DownloadedPodcastGroup] {
    var countByTitle: [String: Int] = [:]
    var imageByTitle: [String: String] = [:]
    for episode in downloadedEpisodes {
      countByTitle[episode.podcastTitle, default: 0] += 1
      if imageByTitle[episode.podcastTitle] == nil, let imageURL = episode.imageURL {
        imageByTitle[episode.podcastTitle] = imageURL
      }
    }

    return countByTitle.map { (title, count) in
      let podcast = podcastTitleMap[title]
      return DownloadedPodcastGroup(
        title: title,
        imageURL: podcast?.imageURL ?? imageByTitle[title],
        podcast: podcast,
        downloadCount: count
      )
    }
    .sorted {
      if $0.downloadCount != $1.downloadCount {
        return $0.downloadCount > $1.downloadCount
      }
      return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
    }
  }

  /// Podcasts sorted by most recent update (combines lastUpdated and latest episode date)
  var podcastsSortedByRecentUpdate: [PodcastInfoModel] {
    podcastInfoModelList.sorted { p1, p2 in
      // Use lastUpdated if available (set during sync), otherwise use latest episode date
        let date1 = p1.lastUpdated
        let date2 = p2.lastUpdated
      return date1 > date2
    }
  }

  private let service = PodcastRssService()
  @ObservationIgnored private let downloadManager = DownloadManager.shared
  private var modelContext: ModelContext?
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "LibraryViewModel")

  // All podcasts (subscribed + browsed) for episode lookups
  private var allPodcasts: [PodcastInfoModel] = []

  // Flag to prevent redundant loads
  private var isAlreadyLoaded = false

  // Flag to prevent redundant disk sync operations
  private var hasSyncedDownloads = false

  // Use Unit Separator (U+001F) as delimiter
  private static let episodeKeyDelimiter = "\u{1F}"

  nonisolated private static func hasLocalAudioFile(_ path: String?) -> Bool {
    guard let path, !path.isEmpty else { return false }
    return FileManager.default.fileExists(atPath: path)
  }

  nonisolated private static func podcastDedupKey(for podcast: PodcastInfoModel) -> String {
    let rss = podcast.rssUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    if !rss.isEmpty { return "rss:\(rss.lowercased())" }
    return "title:\(podcast.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
  }

  // Cache for O(1) lookups
  private var podcastTitleMap: [String: PodcastInfoModel] = [:]

  /// Decoded `PodcastInfo` snapshots keyed by title, rebuilt together with
  /// `podcastTitleMap`. The saved/downloaded loaders previously re-decoded
  /// every podcast's episode blob (`mapValues { $0.podcastInfo }`) on each
  /// refresh — i.e. on every Library appearance — which is main-thread work
  /// proportional to total episode count across the whole library.
  private var podcastInfoByTitle: [String: PodcastInfo] = [:]

  /// (id → lastUpdated) signature of the last `loadAllPodcasts` fetch.
  /// Repeat calls with an unchanged store skip the map rebuilds entirely.
  private var allPodcastsStamp: [UUID: Date] = [:]

  @ObservationIgnored private var initTask: Task<Void, Never>?
  /// Tracks the latest unstructured refresh task so it can be cancelled in cleanup().
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  /// Observes episodeDownloadCompleted notifications for optimistic UI updates.
  @ObservationIgnored private var downloadCompletionTask: Task<Void, Never>?
  /// Observes playbackPositionDidUpdate so list rows reflect current "X left"
  /// without waiting for the user to back out and re-enter the tab.
  @ObservationIgnored private var playbackPositionTask: Task<Void, Never>?
  /// Polls inFlightProgress at 500ms intervals while downloads are active.
  @ObservationIgnored private var progressTimer: Timer?

  init(modelContext: ModelContext?) {
    self.modelContext = modelContext
    if modelContext != nil {
      initTask = Task {
        await loadAll()
      }
    }
    observeDownloadingEpisodes()
    manageProgressTimer()
    observeDownloadCompletions()
    observePlaybackPositionUpdates()
  }

  /// Clean up resources. Call this from onDisappear.
  func cleanup() {
    initTask?.cancel()
    initTask = nil
    refreshTask?.cancel()
    refreshTask = nil
    downloadCompletionTask?.cancel()
    downloadCompletionTask = nil
    playbackPositionTask?.cancel()
    playbackPositionTask = nil
    progressTimer?.invalidate()
    progressTimer = nil
  }

  /// Listen for playback position updates posted by `EnhancedAudioManager`
  /// (every 5s during playback, on pause/seek, and at end-of-episode) and
  /// update the matching `LibraryEpisode` in each visible array. The structs
  /// are immutable snapshots, so we rebuild them in place with the fresh
  /// playback fields — the @Observable array reassignment triggers a row
  /// re-render in any list currently on screen.
  private func observePlaybackPositionUpdates() {
    playbackPositionTask?.cancel()
    playbackPositionTask = Task { [weak self] in
      for await notification in NotificationCenter.default.notifications(named: .playbackPositionDidUpdate) {
        guard let self else { return }
        guard let update = notification.userInfo?["update"] as? PlaybackPositionUpdate else {
          continue
        }
        self.applyPlaybackUpdate(update)
      }
    }
  }

  private func applyPlaybackUpdate(_ update: PlaybackPositionUpdate) {
    let id = "\(update.podcastTitle)\(Self.episodeKeyDelimiter)\(update.episodeTitle)"
    // Mirror PlaybackStateCoordinator's completion threshold so the row's
    // replay icon appears as soon as SwiftData would flip it.
    let isCompleted = update.duration > 0 && (update.duration - update.position) < 30

    savedEpisodes = Self.replacingPlayback(in: savedEpisodes, id: id, position: update.position, duration: update.duration, isCompleted: isCompleted)
    downloadedEpisodes = Self.replacingPlayback(in: downloadedEpisodes, id: id, position: update.position, duration: update.duration, isCompleted: isCompleted)
    latestEpisodes = Self.replacingPlayback(in: latestEpisodes, id: id, position: update.position, duration: update.duration, isCompleted: isCompleted)
  }

  /// Returns `episodes` with the matching id replaced by a fresh `LibraryEpisode`
  /// carrying the new playback fields. Returns the input unchanged when no match
  /// is found, so `@Observable` re-renders only fire when something actually changed.
  private static func replacingPlayback(
    in episodes: [LibraryEpisode],
    id: String,
    position: TimeInterval,
    duration: TimeInterval,
    isCompleted: Bool
  ) -> [LibraryEpisode] {
    guard let index = episodes.firstIndex(where: { $0.id == id }) else { return episodes }
    let existing = episodes[index]
    // Skip if nothing material changed — avoids a needless array write.
    if existing.lastPlaybackPosition == position,
       existing.savedDuration == duration,
       existing.isCompleted == isCompleted {
      return episodes
    }
    var copy = episodes
    copy[index] = LibraryEpisode(
      id: existing.id,
      podcastTitle: existing.podcastTitle,
      imageURL: existing.imageURL,
      language: existing.language,
      episodeInfo: existing.episodeInfo,
      isStarred: existing.isStarred,
      isDownloaded: existing.isDownloaded,
      isCompleted: isCompleted,
      lastPlaybackPosition: position,
      savedDuration: duration
    )
    return copy
  }

  private func observeDownloadCompletions() {
    downloadCompletionTask = Task { [weak self] in
      for await notification in NotificationCenter.default.notifications(named: .episodeDownloadCompleted) {
        guard let self else { return }
        guard let episodeTitle = notification.userInfo?["episodeTitle"] as? String,
              let podcastTitle = notification.userInfo?["podcastTitle"] as? String,
              let localPath = notification.userInfo?["localPath"] as? String else { continue }
        self.handleDownloadCompletion(
          episodeTitle: episodeTitle,
          podcastTitle: podcastTitle,
          localPath: localPath
        )
      }
    }
  }

  private func updateDownloadingEpisodes() {
    var downloading: [DownloadingEpisode] = []
    for (episodeKey, state) in downloadManager.downloadStates {
      let isActive: Bool
      switch state {
      case .downloading, .finishing:
        isActive = true
      default:
        isActive = false
      }
      if isActive {
        if let (podcastTitle, episodeTitle) = parseDownloadEpisodeKey(episodeKey) {
          let imageURL = podcastTitleMap[podcastTitle]?.imageURL
          let progressValue: Double
          if case .finishing = state {
            progressValue = 1.0
          } else {
            progressValue = downloadManager.inFlightProgress[episodeKey] ?? 0
          }
          downloading.append(DownloadingEpisode(
            id: episodeKey,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            imageURL: imageURL,
            progress: progressValue,
            state: state
          ))
        }
      }
    }
    let sorted = downloading.sorted { $0.progress < $1.progress }
    // Only assign if the set of active downloads changed
    if sorted.map(\.id) != downloadingEpisodes.map(\.id) {
      downloadingEpisodes = sorted
    }
  }

  private func observeDownloadingEpisodes() {
    withObservationTracking {
      // Only fires on state transitions (start/finish/fail/cancel),
      // not on progress ticks. Progress is polled by progressTimer.
      _ = downloadManager.downloadStates
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.updateDownloadingEpisodes()
        self.manageProgressTimer()
        self.observeDownloadingEpisodes()
      }
    }
  }

  // MARK: - Progress Timer

  private func manageProgressTimer() {
    if downloadManager.hasActiveDownloads {
      guard progressTimer == nil else { return }
      progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.updateDownloadingProgress()
        }
      }
    } else {
      progressTimer?.invalidate()
      progressTimer = nil
    }
  }

  /// Poll inFlightProgress and update downloadingEpisodes with latest values.
  private func updateDownloadingProgress() {
    for i in downloadingEpisodes.indices {
      let ep = downloadingEpisodes[i]
      if let newProgress = downloadManager.inFlightProgress[ep.id],
         abs(newProgress - ep.progress) > 0.005 {
        downloadingEpisodes[i] = DownloadingEpisode(
          id: ep.id,
          episodeTitle: ep.episodeTitle,
          podcastTitle: ep.podcastTitle,
          imageURL: ep.imageURL,
          progress: newProgress,
          state: .downloading(progress: newProgress)
        )
      }
    }
    // Stop timer if no more active downloads
    if !downloadManager.hasActiveDownloads {
      progressTimer?.invalidate()
      progressTimer = nil
    }
  }

  /// Parse episode key for downloading episodes
  private func parseDownloadEpisodeKey(_ episodeKey: String) -> (podcastTitle: String, episodeTitle: String)? {
    // Try new format first (Unit Separator)
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

  private func handleDownloadCompletion(episodeTitle: String, podcastTitle: String, localPath: String) {
    guard let context = modelContext else { return }

    let episodeKey = "\(podcastTitle)\(Self.episodeKeyDelimiter)\(episodeTitle)"

    // Check if model already exists
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == episodeKey }
    )

    do {
      let updatedModel: EpisodeDownloadModel
      if let existingModel = try context.fetch(descriptor).first {
        existingModel.localAudioPath = localPath
        existingModel.downloadedDate = Date()
        if let attrs = try? FileManager.default.attributesOfItem(atPath: localPath),
           let size = attrs[.size] as? Int64 {
          existingModel.fileSize = size
        }
        try context.save()
        updatedModel = existingModel
      } else {
        // Find the episode from allPodcasts using O(1) lookup
        guard let podcast = podcastTitleMap[podcastTitle] else { return }
        let info = podcast.podcastInfo
        guard let episode = info.episodes.first(where: { $0.title == episodeTitle }),
              let audioURL = episode.audioURL else { return }

        let model = EpisodeDownloadModel(
          episodeTitle: episodeTitle,
          podcastTitle: podcastTitle,
          audioURL: audioURL,
          localAudioPath: localPath,
          downloadedDate: Date(),
          imageURL: episode.imageURL ?? info.imageURL,
          pubDate: episode.pubDate
        )
        if let attrs = try? FileManager.default.attributesOfItem(atPath: localPath),
           let size = attrs[.size] as? Int64 {
          model.fileSize = size
        }
        context.insert(model)
        try context.save()
        updatedModel = model
      }

      // Optimistic update: immediately add to downloadedEpisodes so the episode
      // appears in the list in the same render cycle as it leaves downloadingEpisodes.
      // This prevents a visible flicker where the episode briefly seems to vanish.
      let libraryEpisode = createLibraryEpisode(from: updatedModel)
      if !downloadedEpisodes.contains(where: { $0.id == updatedModel.id }) {
        downloadedEpisodes.insert(libraryEpisode, at: 0)
      } else if let idx = downloadedEpisodes.firstIndex(where: { $0.id == updatedModel.id }) {
        downloadedEpisodes[idx] = libraryEpisode
      }

      // Full async reload for proper sorting and deduplication.
      refreshTask?.cancel()
      refreshTask = Task { await loadDownloadedEpisodesQuick() }
    } catch {
      logger.error("Failed to update download model: \(error.localizedDescription, privacy: .public)")
    }
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context

    // Prevent redundant reloading if data is already loaded
    if isAlreadyLoaded {
      return
    }

    // Start loading in parallel without blocking UI flags.
    // Each section loads independently and updates its own state.
    isRefreshing = true
    isAlreadyLoaded = true

    // Single stored task so cleanup() can cancel it.
    // Podcasts must complete before latest (dependency), then saved/downloaded run in parallel.
    refreshTask = Task {
      // Chain podcasts -> latest to ensure dependencies are met without polling.
      await loadPodcastsSection()
      async let savedTask: () = loadSavedSection()
      async let downloadedTask: () = loadDownloadedSection()
      async let latestTask: () = loadLatestSection()
      _ = await (savedTask, downloadedTask, latestTask)
      isRefreshing = false
    }
  }

  /// Refresh all data sections - called from notification observers.
  func refreshData() {
    guard modelContext != nil else { return }
    // Cancel any in-flight refresh before starting a new one.
    refreshTask?.cancel()
    refreshTask = Task {
      await loadSavedSection()
      await loadDownloadedSection()
      await loadLatestSection()
    }
  }

  /// Receive updated podcast list from View's @Query.
  func setPodcasts(_ podcasts: [PodcastInfoModel]) {
    // Skip the reload if the id-set is unchanged. Prevents cancellation +
    // restart of the latest-episodes refresh task on every Library appearance
    // (the @Query emits a new array on every SwiftData write).
    if podcasts.map(\.id) == podcastInfoModelList.map(\.id) {
      self.podcastInfoModelList = podcasts  // refresh references but no reload
      return
    }
    self.podcastInfoModelList = podcasts
    // Cancel previous refresh; latest episodes depend on the updated podcast list.
    refreshTask?.cancel()
    refreshTask = Task { await loadLatestSection() }
  }

  // MARK: - Independent Section Loaders

  /// Load podcasts section independently
  private func loadPodcastsSection() async {
    await deduplicatePodcastModels()
    // We no longer load feeds manually here, they are injected via setPodcasts
    // Just load the full lookup map
    await loadAllPodcasts()
  }

  private func deduplicatePodcastModels() async {
    guard let context = modelContext else { return }

    let descriptor = FetchDescriptor<PodcastInfoModel>(
      sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
    )

    guard let allPodcasts = try? context.fetch(descriptor), allPodcasts.count > 1 else { return }

    var keptByKey: [String: PodcastInfoModel] = [:]
    var duplicates: [PodcastInfoModel] = []

    for podcast in allPodcasts {
      let key = Self.podcastDedupKey(for: podcast)
      if let existing = keptByKey[key] {
        let keepCurrent = podcast.isSubscribed && !existing.isSubscribed
        if keepCurrent {
          duplicates.append(existing)
          keptByKey[key] = podcast
        } else {
          duplicates.append(podcast)
        }
      } else {
        keptByKey[key] = podcast
      }
    }

    guard !duplicates.isEmpty else { return }

    for duplicate in duplicates {
      context.delete(duplicate)
    }
    try? context.save()
    logger.warning("Removed \(duplicates.count) duplicate PodcastInfoModel entries")
  }

  /// Load saved episodes section independently
  private func loadSavedSection() async {
    // Load immediately - EpisodeDownloadModel has all the data we need
    await loadSavedEpisodes()
  }

  /// Load downloaded episodes section independently
  private func loadDownloadedSection() async {
    // Load downloaded episodes immediately from SwiftData (fast)
    await loadDownloadedEpisodesQuick()

    // Only run heavy disk sync once per session to avoid repeated 1GB memory spikes
    guard !hasSyncedDownloads else { return }
    hasSyncedDownloads = true

    // Sync with disk in the background. Both methods are @MainActor but each
    // performs its own off-main disk I/O via inner Task.detached blocks, so
    // a plain Task here is correct — Task.detached would have only renamed
    // the priority hint without moving any of the heavy work off MainActor.
    Task { [weak self] in
      await self?.syncDownloadedFilesWithSwiftData()
      // Reload to pick up any newly synced episodes
      await self?.loadDownloadedEpisodesQuick()
    }
  }

  /// Load latest episodes section independently
  private func loadLatestSection() async {
    // This section depends heavily on podcastInfoModelList
    // We now await this AFTER loadPodcastsSection completes, so no need to poll
    await loadLatestEpisodes()
  }

  /// Load all sections — shows cached data immediately, syncs disk in background
  private func loadAll() async {
    #if DEBUG
    let signpostID = OSSignpostID(log: signpostLog)
    os_signpost(.begin, log: signpostLog, name: "LibraryViewModel.loadAll", signpostID: signpostID)
    #endif

    isLoading = true

    // First, load all podcasts (needed by other loaders)
    await loadAllPodcasts()

    // Then load the rest using async let for parallelism while staying on MainActor
    // Use loadDownloadedSection (fast path) instead of loadDownloadedEpisodes (slow disk sync)
    async let savedTask: () = loadSavedEpisodes()
    async let downloadedTask: () = loadDownloadedSection()
    async let latestTask: () = loadLatestEpisodes()
    _ = await (savedTask, downloadedTask, latestTask)

    isLoading = false

    #if DEBUG
    os_signpost(.end, log: signpostLog, name: "LibraryViewModel.loadAll", signpostID: signpostID)
    #endif
  }
  // MARK: - Public Refresh Methods

  func refreshSavedEpisodes() async {
    // Non-blocking refresh
    await loadSavedEpisodes()
  }

  func refreshDownloadedEpisodes() async {
    // Downloaded podcasts can include browsed/unsubscribed shows. LibraryView's
    // @Query only tracks subscribed podcasts, so refresh the full lookup here
    // instead of relying on the subscribed snapshot to invalidate this map.
    await loadAllPodcasts()

    // Only run the expensive disk scan once per session.  The scan is already triggered
    // by loadDownloadedSection() during initial load; calling it again on every
    // view re-appearance (tab switch) wastes significant I/O and memory.
    // A pull-to-refresh calls refreshAllPodcasts → loadAll → loadDownloadedSection,
    // which resets hasSyncedDownloads via loadDownloadedSection's detached task,
    // so the scan will run again after a forced refresh.
    guard !hasSyncedDownloads else {
      await loadDownloadedEpisodesQuick()
      return
    }
    await syncDownloadedFilesWithSwiftData()
    await loadDownloadedEpisodesQuick()
  }

  // MARK: - Load All Podcasts (for episode lookups)

  private func loadAllPodcasts() async {
    guard let context = modelContext else { return }

    // Load ALL podcasts (subscribed + browsed) for episode lookups
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
    )

    do {
      let podcasts = try context.fetch(descriptor)

      // Skip the (blob-decoding) map rebuilds when no podcast was added,
      // removed, or refreshed since the last build.
      let stamp = Dictionary(uniqueKeysWithValues: podcasts.map { ($0.id, $0.lastUpdated) })
      if stamp == allPodcastsStamp, !podcastTitleMap.isEmpty {
        self.allPodcasts = podcasts
        return
      }
      allPodcastsStamp = stamp

      // Since we're @MainActor, update directly
      self.allPodcasts = podcasts

      // Decode each podcast's episode blob exactly once, building both lookup
      // maps in a single pass and backfilling the denormalized grid mirrors for
      // any legacy row persisted before those columns existed. (Previously this
      // decoded every blob twice — once for the title map, once for mapValues.)
      var titleMap: [String: PodcastInfoModel] = [:]
      var infoByTitle: [String: PodcastInfo] = [:]
      titleMap.reserveCapacity(podcasts.count)
      infoByTitle.reserveCapacity(podcasts.count)
      var didBackfill = false
      for model in podcasts {
        let info = model.podcastInfo
        titleMap[info.title] = model           // later row wins on duplicate titles
        infoByTitle[info.title] = info
        if model.episodeCount == 0 && !info.episodes.isEmpty {
          model.imageURL = info.imageURL
          model.episodeCount = info.episodes.count
          model.latestEpisodeDate = info.episodes.lazy.compactMap(\.pubDate).max()
          didBackfill = true
        }
      }
      self.podcastTitleMap = titleMap
      self.podcastInfoByTitle = infoByTitle
      if didBackfill { try? context.save() }

      logger.info("Loaded \(self.allPodcasts.count) total podcasts for episode lookups")
    } catch {
      logger.error("Failed to load all podcasts: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Load Podcasts
  
  // Removed loadPodcastFeeds as it's replaced by @Query injection via setPodcasts
  
  // MARK: - Load Saved Episodes

  private func loadSavedEpisodes() async {
    guard let context = modelContext else { return }

    // Predicate filters to only starred rows — avoids full table scan
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.isStarred == true },
      sortBy: [SortDescriptor(\.pubDate, order: .reverse)]
    )

    do {
      let models = try context.fetch(descriptor)
      // Extract Sendable snapshots on MainActor (ModelContext boundary)
      let snapshots = models.map { FullEpisodeSnapshot(from: $0) }
      // Capture cached Sendable lookup map (built in loadAllPodcasts)
      let infoMap = self.podcastInfoByTitle
      let delimiter = Self.episodeKeyDelimiter

      // Dedup + map off the MainActor
      let results = await Task.detached(priority: .userInitiated) { () -> [LibraryEpisode] in
        var seenIds = Set<String>()
        return snapshots.compactMap { snap in
          guard seenIds.insert(snap.id).inserted else { return nil }
          return Self.makeLibraryEpisode(from: snap, podcastInfoMap: infoMap, delimiter: delimiter)
        }
      }.value

      // Assign only on real change — an unconditional write invalidates every
      // observer (Library body, QuickAccess counts) even when nothing moved.
      if results != self.savedEpisodes {
        self.savedEpisodes = results
      }
      logger.info("Loaded \(self.savedEpisodes.count) saved episodes")
    } catch {
      logger.error("Failed to load saved episodes: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Load Downloaded Episodes

  /// Quick load from SwiftData without disk sync (for responsive UI)
  private func loadDownloadedEpisodesQuick() async {
    guard let context = modelContext else { return }

    // Predicate filters to only rows with a local path — avoids full table scan
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.localAudioPath != nil },
      sortBy: [SortDescriptor(\.pubDate, order: .reverse)]
    )

    do {
      let models = try context.fetch(descriptor)
      // Extract Sendable snapshots on MainActor (ModelContext boundary)
      let snapshots = models.map { FullEpisodeSnapshot(from: $0) }
      // Capture cached Sendable lookup map (built in loadAllPodcasts)
      let infoMap = self.podcastInfoByTitle
      let delimiter = Self.episodeKeyDelimiter

      // Dedup + map off the MainActor
      let results = await Task.detached(priority: .userInitiated) { () -> [LibraryEpisode] in
        var seenIds = Set<String>()
        return snapshots.compactMap { snap in
          guard Self.hasLocalAudioFile(snap.localAudioPath) else { return nil }
          guard seenIds.insert(snap.id).inserted else { return nil }
          return Self.makeLibraryEpisode(from: snap, podcastInfoMap: infoMap, delimiter: delimiter)
        }
      }.value

      // Assign only on real change — an unconditional write invalidates every
      // observer (Library body, QuickAccess counts) even when nothing moved.
      if results != self.downloadedEpisodes {
        self.downloadedEpisodes = results
      }
      logger.info("Quick loaded \(self.downloadedEpisodes.count) downloaded episodes")
    } catch {
      logger.error("Download fetch failed: \(error, privacy: .public)")
    }
  }

  /// Full load with disk sync (for refresh operations)
  private func loadDownloadedEpisodes() async {
    guard let context = modelContext else { return }

    // First, sync SwiftData with actual files on disk
    // This handles cases where downloads completed while no observer was listening
    await syncDownloadedFilesWithSwiftData()

    // Fetch ALL EpisodeDownloadModel and filter in memory
    // This avoids potential SwiftData predicate issues with Unicode strings
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      sortBy: [SortDescriptor(\.pubDate, order: .reverse)]
    )

    do {
      let allModels = try context.fetch(descriptor)
      logger.info("Fetched \(allModels.count) total EpisodeDownloadModel entries")

      // Filter for downloaded episodes in memory (localAudioPath is not nil and not empty)
      let downloadedModels = allModels.filter { model in
        return model.hasLocalAudioFile
      }
      logger.info("Found \(downloadedModels.count) models with localAudioPath")

      // Map to LibraryEpisode - always succeeds due to fallback
      let results = downloadedModels.map { model in
        self.createLibraryEpisode(from: model)
      }
      self.downloadedEpisodes = results
      logger.info("Loaded \(self.downloadedEpisodes.count) downloaded episodes")
    } catch {
      logger.error("Download fetch failed: \(error, privacy: .public)")
    }
  }

  /// Reconciles `EpisodeDownloadModel.localAudioPath` against the audio
  /// directory on disk. `EpisodeDownloadModel` is the single source of truth
  /// for download state — this routine only ensures every row's `localAudioPath`
  /// reflects reality.
  ///
  /// Three passes, all driven by the model (not by `PodcastInfoModel`), so
  /// downloads belonging to unsubscribed or removed podcasts are reconciled
  /// the same as subscribed ones — fixes the bug where files survived a
  /// sandbox-container rotation but never reappeared in the Downloaded tab
  /// because discovery only iterated subscribed podcasts.
  ///
  /// 1. De-dup `EpisodeDownloadModel` rows that share an id.
  /// 2. For every row, align `localAudioPath` with what's on disk:
  ///    - If the stored path still resolves: keep it.
  ///    - Else look up by expected `sanitize("{podcastTitle}_{episodeTitle}")`.
  ///    - Else clear (file truly gone).
  /// 3. Discover audio files no row claims, match them back to a
  ///    `PodcastInfoModel` episode, and create a new row. Files with no
  ///    matching episode anywhere are left alone (can't be unambiguously
  ///    reversed from their sanitized filename).
  private func syncDownloadedFilesWithSwiftData() async {
    #if DEBUG
    let signpostID = OSSignpostID(log: signpostLog)
    os_signpost(.begin, log: signpostLog, name: "LibraryViewModel.syncDisk", signpostID: signpostID)
    defer { os_signpost(.end, log: signpostLog, name: "LibraryViewModel.syncDisk", signpostID: signpostID) }
    #endif

    guard let context = modelContext else { return }

    // 1. Fetch every download row.
    let descriptor = FetchDescriptor<EpisodeDownloadModel>()
    let allModels: [EpisodeDownloadModel]
    do {
      allModels = try context.fetch(descriptor)
    } catch {
      logger.error("Failed to fetch models for sync: \(error, privacy: .public)")
      return
    }

    // 1b. De-duplicate rows that share an id.
    let modelsById = Dictionary(allModels.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
    if modelsById.count < allModels.count {
      let duplicateCount = allModels.count - modelsById.count
      let keptIds = Set(modelsById.values.map { ObjectIdentifier($0) })
      for model in allModels where !keptIds.contains(ObjectIdentifier(model)) {
        context.delete(model)
      }
      try? context.save()
      logger.warning("Removed \(duplicateCount) duplicate EpisodeDownloadModel entries")
    }

    // 2. Single off-MainActor scan of the audio directory.
    let audioFileIndex = await Task.detached(priority: .background) { () -> [String: String] in
      let fm = FileManager.default
      let audioDir = FileStorageManager.platformAudioDirectory(fileManager: fm)

      var index: [String: String] = [:]  // lowercased basename → full path
      guard let contents = try? fm.contentsOfDirectory(
        at: audioDir, includingPropertiesForKeys: nil
      ) else { return index }
      for url in contents {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        index[name] = url.path
      }
      return index
    }.value

    let pathsOnDisk = Set(audioFileIndex.values)

    // 3. Reconcile every row's localAudioPath against disk reality.
    //    Uses the row's own podcastTitle/episodeTitle, so podcasts whose
    //    PodcastInfoModel was deleted are reconciled the same as subscribed.
    var pathChanges = 0
    var claimedBasenames = Set<String>()
    for model in modelsById.values {
      // Happy path: stored path still resolves.
      if let existing = model.localAudioPath, pathsOnDisk.contains(existing) {
        let basename = URL(fileURLWithPath: existing)
          .deletingPathExtension().lastPathComponent.lowercased()
        claimedBasenames.insert(basename)
        continue
      }

      // Repair (sandbox rotation, manual relocation, etc.) via expected basename.
      let expected = Self.sanitizeFileName("\(model.podcastTitle)_\(model.episodeTitle)").lowercased()
      let repaired = audioFileIndex[expected]

      if model.localAudioPath != repaired {
        model.localAudioPath = repaired
        if repaired != nil, model.downloadedDate == nil {
          model.downloadedDate = Date()
        }
        pathChanges += 1
      }
      if repaired != nil { claimedBasenames.insert(expected) }
    }

    // 4. Discover audio files no row claims. Match each against an episode
    //    in any podcast we know about, and create a row for it.
    let delimiter = Self.episodeKeyDelimiter
    var discoveredCount = 0
    let orphans = audioFileIndex.filter { !claimedBasenames.contains($0.key) }
    if !orphans.isEmpty {
      var episodesByBasename: [String: (PodcastInfo, PodcastEpisodeInfo)] = [:]
      for podcast in allPodcasts {
        let info = podcast.podcastInfo
        for episode in info.episodes {
          let key = Self.sanitizeFileName("\(info.title)_\(episode.title)").lowercased()
          episodesByBasename[key] = (info, episode)
        }
      }

      for (basename, fullPath) in orphans {
        guard let (info, episode) = episodesByBasename[basename] else { continue }
        let modelKey = "\(info.title)\(delimiter)\(episode.title)"
        guard modelsById[modelKey] == nil, let audioURL = episode.audioURL else { continue }
        let newModel = EpisodeDownloadModel(
          episodeTitle: episode.title,
          podcastTitle: info.title,
          audioURL: audioURL,
          localAudioPath: fullPath,
          downloadedDate: Date(),
          imageURL: episode.imageURL ?? info.imageURL,
          pubDate: episode.pubDate
        )
        context.insert(newModel)
        discoveredCount += 1
      }
    }

    if pathChanges > 0 || discoveredCount > 0 {
      try? context.save()
      logger.info("Sync: updated \(pathChanges) paths, discovered \(discoveredCount) new models")
    }
  }

  /// Sanitize a filename by replacing invalid characters with underscores.
  /// Matches the same logic as the former `checkAudioFileExists` and `FileStorageManager`.
  /// Pure function — nonisolated so it can be called from any isolation context.
  nonisolated private static func sanitizeFileName(_ name: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
    return name
      .components(separatedBy: invalidCharacters)
      .joined(separator: "_")
      .trimmingCharacters(in: .whitespaces)
  }

  /// Construct a LibraryEpisode from a Sendable snapshot; safe to call from any isolation context.
  nonisolated private static func makeLibraryEpisode(
    from snap: FullEpisodeSnapshot,
    podcastInfoMap: [String: PodcastInfo],
    delimiter: String
  ) -> LibraryEpisode {
    // Try to enrich with live podcast info
    if let delimiterRange = snap.id.range(of: delimiter) {
      let podcastTitle = String(snap.id[..<delimiterRange.lowerBound])
      let episodeTitle = String(snap.id[delimiterRange.upperBound...])
      if podcastTitle == snap.podcastTitle && episodeTitle == snap.episodeTitle,
         let podcast = podcastInfoMap[podcastTitle],
         let episode = podcast.episodes.first(where: { $0.title == episodeTitle }) {
        return LibraryEpisode(
          id: snap.id,
          podcastTitle: podcastTitle,
          imageURL: episode.imageURL ?? podcast.imageURL,
          language: podcast.language,
          episodeInfo: episode,
          isStarred: snap.isStarred,
          isDownloaded: Self.hasLocalAudioFile(snap.localAudioPath),
          isCompleted: snap.isCompleted,
          lastPlaybackPosition: snap.lastPlaybackPosition,
          savedDuration: snap.duration
        )
      }
    }
    // Fallback: build from stored data (handles unsubscribed podcasts, special characters, etc.)
    let durationSeconds: Int? = snap.duration > 0 ? Int(snap.duration) : nil
    let episodeInfo = PodcastEpisodeInfo(
      title: snap.episodeTitle,
      podcastEpisodeDescription: nil,
      pubDate: snap.pubDate,
      audioURL: snap.audioURL,
      imageURL: snap.imageURL,
      duration: durationSeconds,
      guid: nil
    )
    return LibraryEpisode(
      id: snap.id,
      podcastTitle: snap.podcastTitle,
      imageURL: snap.imageURL,
      language: "",
      episodeInfo: episodeInfo,
      isStarred: snap.isStarred,
      isDownloaded: Self.hasLocalAudioFile(snap.localAudioPath),
      isCompleted: snap.isCompleted,
      lastPlaybackPosition: snap.lastPlaybackPosition,
      savedDuration: snap.duration
    )
  }

  // MARK: - Load Latest Episodes

  private func loadLatestEpisodes() async {
    guard let context = modelContext else { return }

    // 1. Gather all necessary data on MainActor (where ModelContext lives)
    let descriptor = FetchDescriptor<EpisodeDownloadModel>()
    let episodeDataDict: [String: EpisodeDownloadData]
    do {
      let allModels = try context.fetch(descriptor)
      // Map to Sendable DTOs
      let keyValues = allModels.map { model in
        (model.id, EpisodeDownloadData(
          id: model.id,
          isStarred: model.isStarred,
          localAudioPath: model.localAudioPath,
          isCompleted: model.isCompleted,
          lastPlaybackPosition: model.lastPlaybackPosition,
          duration: model.duration
        ))
      }
      episodeDataDict = Dictionary(keyValues, uniquingKeysWith: { _, latest in latest })
    } catch {
      logger.error("Failed to fetch episode models: \(error, privacy: .public)")
      return
    }

    // Reuse the episode blobs already decoded by loadAllPodcasts (keyed by the
    // reliable title mirror) so we don't re-decode every subscribed podcast on
    // the main actor here. Falls back to a direct decode only when the cache
    // isn't warm yet (e.g. setPodcasts → loadLatestSection raced ahead of it).
    let infoByTitle = self.podcastInfoByTitle
    let podcasts: [PodcastInfo] = self.podcastInfoModelList.map { model in
      infoByTitle[model.title] ?? model.podcastInfo
    }

    // 2. Perform heavy processing in background
    let delimiter = Self.episodeKeyDelimiter
    
    let sortedEpisodes = await Task.detached(priority: .userInitiated) { () -> [LibraryEpisode] in
      var allEpisodes: [LibraryEpisode] = []

      for podcastInfo in podcasts {
        // Get latest 5 episodes from each podcast
        for episode in podcastInfo.episodes.prefix(5) {
          let episodeKey = "\(podcastInfo.title)\(delimiter)\(episode.title)"
          let data = episodeDataDict[episodeKey]

          allEpisodes.append(LibraryEpisode(
            id: episodeKey,
            podcastTitle: podcastInfo.title,
            imageURL: episode.imageURL ?? podcastInfo.imageURL,
            language: podcastInfo.language,
            episodeInfo: episode,
            isStarred: data?.isStarred ?? false,
            isDownloaded: Self.hasLocalAudioFile(data?.localAudioPath),
            isCompleted: data?.isCompleted ?? false,
            lastPlaybackPosition: data?.lastPlaybackPosition ?? 0,
            savedDuration: data?.duration ?? 0
          ))
        }
      }

      // Sort by date and take latest 50
      return allEpisodes
        .sorted { ($0.episodeInfo.pubDate ?? .distantPast) > ($1.episodeInfo.pubDate ?? .distantPast) }
        .prefix(50)
        .map { $0 } // Convert SubSequence back to Array
    }.value

    // 3. Update UI on MainActor
    self.latestEpisodes = sortedEpisodes
    logger.info("Loaded \(self.latestEpisodes.count) latest episodes (background processed)")

    // Update auto-play candidates
    updateAutoPlayCandidates()
  }

  /// Update the audio manager's auto-play candidates with unplayed episodes.
  /// Sorted: in-progress first (by saved position desc), then newest by pubDate.
  /// HomeViewModel will replace this list with the fully-scored Up Next order
  /// once the Home tab loads; this acts as a sensible fallback.
  private func updateAutoPlayCandidates() {
    let unplayedEpisodes = latestEpisodes
      .filter { !$0.isCompleted }
      .sorted { a, b in
        let aInProgress = a.lastPlaybackPosition > 60
        let bInProgress = b.lastPlaybackPosition > 60
        if aInProgress != bInProgress { return aInProgress }
        if aInProgress && bInProgress { return a.lastPlaybackPosition > b.lastPlaybackPosition }
        return (a.episodeInfo.pubDate ?? .distantPast) > (b.episodeInfo.pubDate ?? .distantPast)
      }
    let playbackEpisodes = unplayedEpisodes.compactMap { episode -> PlaybackEpisode? in
      guard let audioURL = episode.episodeInfo.audioURL else { return nil }
      return PlaybackEpisode(
        id: episode.id,
        title: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: audioURL,
        imageURL: episode.imageURL,
        episodeDescription: episode.episodeInfo.podcastEpisodeDescription,
        pubDate: episode.episodeInfo.pubDate,
        duration: episode.episodeInfo.duration,
        guid: episode.episodeInfo.guid
      )
    }
    EnhancedAudioManager.shared.updateAutoPlayCandidates(playbackEpisodes)
    logger.info("Updated auto-play candidates with \(playbackEpisodes.count) unplayed episodes")
  }



  // MARK: - Helper Methods

  /// Create a LibraryEpisode from EpisodeDownloadModel - always succeeds using stored data
  private func createLibraryEpisode(from model: EpisodeDownloadModel) -> LibraryEpisode {
    // Try to find full episode info from podcasts first
    if let (podcastTitle, episodeTitle) = parseEpisodeKey(model.id) {
      // Verify parsed titles match stored titles (catches mis-parsing due to | in episode titles)
      if podcastTitle == model.podcastTitle && episodeTitle == model.episodeTitle {
        // Try to find full podcast info for richer data using O(1) lookup.
        // `info` is bound once: this runs per episode, and each read of
        // `podcast.podcastInfo` re-materializes the whole episode array.
        if let podcast = podcastTitleMap[podcastTitle] {
          let info = podcast.podcastInfo
          if let episode = info.episodes.first(where: { $0.title == episodeTitle }) {
            return LibraryEpisode(
              id: model.id,
              podcastTitle: podcastTitle,
              imageURL: episode.imageURL ?? info.imageURL,
              language: info.language,
              episodeInfo: episode,
              isStarred: model.isStarred,
              isDownloaded: Self.hasLocalAudioFile(model.localAudioPath),
              isCompleted: model.isCompleted,
              lastPlaybackPosition: model.lastPlaybackPosition,
              savedDuration: model.duration
            )
          }
        }
      }
    }

    // Fallback: use the stored data from EpisodeDownloadModel directly
    // This handles episodes with special characters, unsubscribed podcasts, etc.
    let durationSeconds: Int? = model.duration > 0 ? Int(model.duration) : nil
    let episodeInfo = PodcastEpisodeInfo(
      title: model.episodeTitle,
      podcastEpisodeDescription: nil,
      pubDate: model.pubDate,
      audioURL: model.audioURL,
      imageURL: model.imageURL,
      duration: durationSeconds,
      guid: nil
    )

    return LibraryEpisode(
      id: model.id,
      podcastTitle: model.podcastTitle,
      imageURL: model.imageURL,
      language: "",
      episodeInfo: episodeInfo,
      isStarred: model.isStarred,
      isDownloaded: Self.hasLocalAudioFile(model.localAudioPath),
      isCompleted: model.isCompleted,
      lastPlaybackPosition: model.lastPlaybackPosition,
      savedDuration: model.duration
    )
  }

  /// Parse episode key, supporting both new format (Unit Separator) and old format (|) for backward compatibility
  private func parseEpisodeKey(_ episodeKey: String) -> (podcastTitle: String, episodeTitle: String)? {
    // Try new format first (Unit Separator)
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

  private func findEpisodeInfo(for model: EpisodeDownloadModel) -> LibraryEpisode? {
    // Parse the episode key to get podcast title and episode title
    guard let (podcastTitle, episodeTitle) = parseEpisodeKey(model.id) else {
      logger.warning("Failed to parse episode key: \(model.id)")
      // Fallback: use the stored data from EpisodeDownloadModel
      return createFallbackLibraryEpisode(from: model)
    }

    // Find the podcast using O(1) lookup. `info` is bound once — this runs per
    // episode, and each `podcast.podcastInfo` read re-materializes the array.
    if let podcast = podcastTitleMap[podcastTitle] {
      let info = podcast.podcastInfo
      if let episode = info.episodes.first(where: { $0.title == episodeTitle }) {
        // Found the full episode info
        return LibraryEpisode(
          id: model.id,
          podcastTitle: podcastTitle,
          imageURL: episode.imageURL ?? info.imageURL,
          language: info.language,
          episodeInfo: episode,
          isStarred: model.isStarred,
          isDownloaded: Self.hasLocalAudioFile(model.localAudioPath),
          isCompleted: model.isCompleted,
          lastPlaybackPosition: model.lastPlaybackPosition,
          savedDuration: model.duration
        )
      }
    }

    // Fallback: use the stored data from EpisodeDownloadModel
    // This handles cases where the podcast was unsubscribed or episode removed from RSS
    return createFallbackLibraryEpisode(from: model)
  }

  /// Create a LibraryEpisode from EpisodeDownloadModel's stored data when the podcast isn't in the database
  private func createFallbackLibraryEpisode(from model: EpisodeDownloadModel) -> LibraryEpisode {
    // Create a minimal PodcastEpisodeInfo from the stored data
    let durationSeconds: Int? = model.duration > 0 ? Int(model.duration) : nil
    let episodeInfo = PodcastEpisodeInfo(
      title: model.episodeTitle,
      podcastEpisodeDescription: nil,
      pubDate: model.pubDate,
      audioURL: model.audioURL,
      imageURL: model.imageURL,
      duration: durationSeconds,
      guid: nil
    )

    return LibraryEpisode(
      id: model.id,
      podcastTitle: model.podcastTitle,
      imageURL: model.imageURL,
      language: "en",  // Default language when unknown
      episodeInfo: episodeInfo,
      isStarred: model.isStarred,
      isDownloaded: Self.hasLocalAudioFile(model.localAudioPath),
      isCompleted: model.isCompleted,
      lastPlaybackPosition: model.lastPlaybackPosition,
      savedDuration: model.duration
    )
  }

  private func getEpisodeModel(for key: String) -> EpisodeDownloadModel? {
    guard let context = modelContext else { return nil }

    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )

    return try? context.fetch(descriptor).first
  }

  // MARK: - Refresh All Podcasts

  func refreshAllPodcasts() async {
    guard let context = modelContext else {
      logger.warning("ModelContext is nil, cannot refresh")
      return
    }

    isLoading = true
    error = nil

    let podcastCount = self.podcastInfoModelList.count
    logger.info("Starting parallel refresh of \(podcastCount) podcast feeds")

    // Extract RSS URLs and model IDs before entering TaskGroup
    let modelData: [(id: UUID, rssUrl: String)] = self.podcastInfoModelList.map { ($0.id, $0.podcastInfo.rssUrl) }

    // Use TaskGroup to fetch all podcasts in parallel
    let results = await withTaskGroup(of: (UUID, PodcastInfo?).self) { group -> [(UUID, PodcastInfo?)] in
      for (id, rssUrl) in modelData {
        group.addTask {
          do {
            let updatedPodcast = try await self.service.fetchPodcast(from: rssUrl)
            return (id, updatedPodcast)
          } catch {
            return (id, nil)
          }
        }
      }

      var collected: [(UUID, PodcastInfo?)] = []
      for await result in group {
        collected.append(result)
      }
      return collected
    }

    // Update models and set lastUpdated timestamp
    var successCount = 0
    let now = Date()
    for (id, updatedPodcast) in results {
      if let podcast = updatedPodcast,
         let model = self.podcastInfoModelList.first(where: { $0.id == id }) {
        model.applyPodcastInfo(podcast)
        model.lastUpdated = now  // Update timestamp for proper sorting
        successCount += 1
        logger.info("Updated \(podcast.title) with \(podcast.episodes.count) episodes")
      }
    }
    logger.info("Successfully refreshed \(successCount)/\(podcastCount) podcasts")

    // Save changes
    do {
      try context.save()
      logger.info("Saved all podcast updates")
    } catch {
      logger.error("Failed to save updates: \(error.localizedDescription, privacy: .public)")
    }

    // Reload all data
    await loadAll()

    isLoading = false
    logger.info("Finished refreshing all podcasts")
  }
}
