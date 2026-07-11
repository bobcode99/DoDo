//
//  HomeViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for Home tab - manages Up Next episodes and Popular Shows from Apple
//

import SwiftUI
import Foundation
import Observation
import SwiftData
import OSLog

@MainActor
@Observable
final class HomeViewModel {
  // Static cache shared across all instances to prevent duplicate API calls
  private static var cachedTopPodcasts: [AppleRSSPodcast] = []
  private static var cachedRegion: String = ""
  // Replace boolean flag with Task to allow joining
  private static var loadingTask: Task<[AppleRSSPodcast], Error>?
  private static var loadingRegion: String?

  // Up Next episodes (unplayed from subscribed podcasts)
  var upNextEpisodes: [LibraryEpisode] = []
  // Scored version — used by HomeView cards to show reason badges
  var scoredUpNextEpisodes: [ScoredEpisode] = []
  /// Stable ID list for `.animation(value:)` — avoids allocating a new array in view body.
  var scoredUpNextIDs: [String] { scoredUpNextEpisodes.map(\.id) }

  /// Number of in-progress (Continue Listening) episodes in the Up Next list,
  /// excluding the currently playing episode.  Used by the view to show the section subtitle.
  var continueListeningCount: Int {
    let nowPlayingId = EnhancedAudioManager.shared.currentEpisode?.id
    return scoredUpNextEpisodes.filter { scored in
      guard scored.episode.id != nowPlayingId else { return false }
      if case .inProgress = scored.reason { return true }
      return false
    }.count
  }

  // Top podcasts from Apple RSS - observable instance properties that sync with static cache
  var topPodcasts: [AppleRSSPodcast] = []
  var isLoadingTopPodcasts = false

  /// When the currently-shown Popular Shows list was fetched from the network — or,
  /// when painted from the on-disk cache, that cache's saved time. Drives the
  /// freshness caption ("Updated 2h ago" / "Offline · saved 2h ago").
  var popularShowsFetchedAt: Date?

  /// True once a successful *network* fetch has populated Popular Shows this session.
  /// Gates reconnect-refresh so a Wi-Fi blip doesn't reshuffle an already-fresh list.
  @ObservationIgnored
  private var hasFreshPopularShowsThisSession = false

  /// Region the currently-displayed `topPodcasts` belong to (from disk hydrate, the
  /// in-memory cache, or a network fetch). Lets a refresh keep the list on screen for
  /// a same-region swap and only blank it when actually switching regions.
  @ObservationIgnored
  private var displayedRegion: String?

  /// True when connectivity has been determined and we're offline. Lets Popular Shows
  /// caption itself as saved/offline instead of showing a load error.
  var isOffline: Bool {
    NetworkMonitor.shared.hasReceivedFirstUpdate && !NetworkMonitor.shared.isConnected
  }

  // Trending episodes from top podcasts
  var trendingEpisodes: [ApplePodcastService.TrendingEpisode] = []
  var isLoadingTrendingEpisodes = false

  // Region selection - synced with Settings
  var selectedRegion: String = "us" {
    didSet {
      if oldValue != selectedRegion {
        // Save to UserDefaults for consistency
        UserDefaults.standard.set(selectedRegion, forKey: "selectedPodcastRegion")
        regionChangeTask?.cancel()
        if isHomeVisible {
          regionChangeTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshDiscoveryContent(forceRefresh: true)
          }
        } else {
          needsDiscoveryRefresh = true
          invalidateDiscoveryContent()
        }
      }
    }
  }

  // For You recommendations (on-device AI)
  var isLoadingRecommendations = false
  var recommendedEpisodes: [LibraryEpisode] = []

  @ObservationIgnored
  private var recommendationsTask: Task<Void, Never>?

  @ObservationIgnored
  private var loadTask: Task<Void, Never>?

  @ObservationIgnored
  private var subscribeTask: Task<Void, Never>?

  @ObservationIgnored
  private var regionChangeTask: Task<Void, Never>?


  @ObservationIgnored
  private var podcastInfoModelList: [PodcastInfoModel] = []

  @ObservationIgnored
  private let applePodcastService = ApplePodcastService()

  @ObservationIgnored
  private let rssService = PodcastRssService()

  @ObservationIgnored
  private var modelContext: ModelContext?

  @ObservationIgnored
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "HomeViewModel")

  // Flag to prevent redundant loads
  @ObservationIgnored
  private var hasLoadedInitialContent = false

  @ObservationIgnored
  private var isHomeVisible = false

  @ObservationIgnored
  private var needsDiscoveryRefresh = false

  // Task for region change observation
  @ObservationIgnored
  private var regionObserverTask: Task<Void, Never>?

  // Task for episode completion observation
  @ObservationIgnored
  private var completionObserverTask: Task<Void, Never>?

  // Task observing connectivity restoration to refresh stale discovery content
  @ObservationIgnored
  private var reconnectObserverTask: Task<Void, Never>?

  // Task observing background/foreground sync completion so new episodes
  // appear on Home without a pull-to-refresh
  @ObservationIgnored
  private var syncObserverTask: Task<Void, Never>?

  // Track current playing episode to detect changes
  @ObservationIgnored
  private var lastCurrentEpisodeId: String?

  // Use Unit Separator (U+001F) as delimiter
  private static let episodeKeyDelimiter = "\u{1F}"

  nonisolated private static func hasLocalAudioFile(_ path: String?) -> Bool {
    guard let path, !path.isEmpty else { return false }
    return FileManager.default.fileExists(atPath: path)
  }

  private static func isEpisodeInProgress(model: EpisodeDownloadModel?) -> Bool {
    guard let model else { return false }
    return model.lastPlaybackPosition > UpNextSuggestionEngine.inProgressMinSeconds
  }

  /// Whether the "For You" section should be shown (cached from UserDefaults)
  var showForYouRecommendations: Bool {
    UserDefaults.standard.object(forKey: "showForYouRecommendations") == nil ||
    UserDefaults.standard.bool(forKey: "showForYouRecommendations")
  }

  /// Whether the "Top Episodes" section should be shown (cached from UserDefaults)
  var showTrendingEpisodes: Bool {
    UserDefaults.standard.object(forKey: "showTrendingEpisodes") == nil ||
    UserDefaults.standard.bool(forKey: "showTrendingEpisodes")
  }

  var selectedRegionName: String {
    if let region = Constants.podcastRegions.first(where: { $0.code == selectedRegion }) {
      return "\(region.flag) \(region.name)"
    }
    return selectedRegion.uppercased()
  }

  var selectedRegionFlag: String {
    Constants.podcastRegions.first { $0.code == selectedRegion }?.flag ?? "🌍"
  }

  init() {
    // Restore saved region preference, else default to the device's locale region
    if let saved = UserDefaults.standard.string(forKey: "selectedPodcastRegion") {
      selectedRegion = saved
    } else {
      selectedRegion = Constants.defaultRegion
    }

    // Restore from static cache if available for current region
    if !Self.cachedTopPodcasts.isEmpty && Self.cachedRegion == selectedRegion {
      topPodcasts = Self.cachedTopPodcasts
    }
    // Otherwise paint Popular Shows from the on-disk cache for an instant first frame
    // (works with no internet too); a network refresh later swaps in fresh data.
    hydratePopularShowsFromDisk()

    // Observers are started lazily in restartObserversIfNeeded() (called from setModelContext),
    // so they survive tab-switch cleanup/onAppear cycles without creating duplicates.

    // Refresh Up Next when the currently playing episode changes
    startCurrentEpisodeObserver()
  }

  /// Observe EnhancedAudioManager.currentEpisode for changes and reload Up Next
  private func startCurrentEpisodeObserver() {
    // Use withObservationTracking to detect when currentEpisode changes
    withObservationTracking {
      _ = EnhancedAudioManager.shared.currentEpisode
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let newId = EnhancedAudioManager.shared.currentEpisode?.id
        if newId != self.lastCurrentEpisodeId {
          self.lastCurrentEpisodeId = newId
          await self.loadUpNextEpisodes()
        }
        // Re-register for next change
        self.startCurrentEpisodeObserver()
      }
    }
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    isHomeVisible = true
    // Restart long-lived observers that cleanup() may have cancelled on tab switch.
    restartObserversIfNeeded()
    if !hasLoadedInitialContent {
      startInitialLoadIfNeeded()
    } else if needsDiscoveryRefresh {
      regionChangeTask?.cancel()
      regionChangeTask = Task { [weak self] in
        guard let self else { return }
        await self.refreshDiscoveryContent(forceRefresh: true)
      }
    }
  }

  /// Restart notification-observer tasks that are cancelled by cleanup() on tab switch.
  /// Safe to call multiple times — only creates a new task when the existing one is nil.
  private func restartObserversIfNeeded() {
    if regionObserverTask == nil {
      regionObserverTask = Task {
        for await notification in NotificationCenter.default.notifications(named: .podcastRegionChanged) {
          if let newRegion = notification.object as? String {
            selectedRegion = newRegion
          }
        }
      }
    }
    if completionObserverTask == nil {
      completionObserverTask = Task {
        for await _ in NotificationCenter.default.notifications(named: .episodeCompletionChanged) {
          await loadUpNextEpisodes()
        }
      }
    }
    if reconnectObserverTask == nil {
      reconnectObserverTask = Task { [weak self] in
        for await _ in NotificationCenter.default.notifications(named: .networkDidReconnect) {
          guard let self, self.isHomeVisible else { continue }
          // Only refresh when we're showing stale (disk-cached) or empty content —
          // never reshuffle a list that's already fresh this session.
          guard !self.hasFreshPopularShowsThisSession || self.topPodcasts.isEmpty else { continue }
          await self.refreshDiscoveryContent(forceRefresh: true)
        }
      }
    }
    if syncObserverTask == nil {
      syncObserverTask = Task { [weak self] in
        for await notification in NotificationCenter.default.notifications(named: .podcastSyncCompleted) {
          guard let self else { return }
          // Only reload when the sync actually found episodes — the notification
          // also fires for timestamp-only updates.
          let newCount = notification.userInfo?["newEpisodeCount"] as? Int ?? 0
          guard newCount > 0 else { continue }
          await self.loadPodcastFeeds()
          await self.loadUpNextEpisodes()
        }
      }
    }
  }

  // MARK: - Load All Data

  private func loadAll(forceRefresh: Bool = false) async {
    // Load feeds first, then episodes (episodes depend on feeds)
    await loadPodcastFeeds()
    // Load up next and top podcasts in parallel
    async let upNextTask: () = loadUpNextEpisodes()
    async let topPodcastsTask: () = loadTopPodcasts(forceRefresh: forceRefresh)
    _ = await (upNextTask, topPodcastsTask)
    // Trending depends on topPodcasts being loaded
    await loadTrendingEpisodes(forceRefresh: forceRefresh)

    // Load recommendations after feeds are loaded
    if #available(iOS 26.0, macOS 26.0, *) {
      loadRecommendations()
    }
  }

  func refresh() async {
    needsDiscoveryRefresh = false
    await loadAll(forceRefresh: true)
    hasLoadedInitialContent = true
  }

  private func startInitialLoadIfNeeded() {
    guard loadTask == nil else { return }

    loadTask = Task { [weak self] in
      guard let self else { return }
      defer { self.loadTask = nil }

      await self.loadAll()

      if !Task.isCancelled {
        self.hasLoadedInitialContent = true
        self.needsDiscoveryRefresh = false
      }
    }
  }

  private func refreshDiscoveryContent(forceRefresh: Bool) async {
    await loadTopPodcasts(forceRefresh: forceRefresh)
    await loadTrendingEpisodes(forceRefresh: forceRefresh)

    if !Task.isCancelled {
      needsDiscoveryRefresh = false
    }
  }

  private func invalidateDiscoveryContent() {
    topPodcasts = []
    trendingEpisodes = []
    isLoadingTopPodcasts = false
    isLoadingTrendingEpisodes = false
    popularShowsFetchedAt = nil
    hasFreshPopularShowsThisSession = false
    displayedRegion = nil
    Self.cachedTopPodcasts = []
    Self.cachedTrendingEpisodes = []
    Self.cachedRegion = ""
    Self.cachedTrendingRegion = ""
  }

  // MARK: - Load Podcasts

  private func loadPodcastFeeds() async {
    guard let context = modelContext else { return }

    // Only load subscribed podcasts (not browsed/cached ones)
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.isSubscribed == true },
      sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
    )

    do {
      podcastInfoModelList = try context.fetch(descriptor)
      logger.info("Loaded \(self.podcastInfoModelList.count) subscribed podcasts")
    } catch {
      logger.error("Failed to load podcasts: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Up Next Episodes

  private func loadUpNextEpisodes() async {
    guard let context = modelContext else { return }

    // Batch fetch all EpisodeDownloadModels once (instead of N+1 individual queries)
    let allDescriptor = FetchDescriptor<EpisodeDownloadModel>()
    let allModels = (try? context.fetch(allDescriptor)) ?? []
    var modelsByKey: [String: EpisodeDownloadModel] = [:]
    for model in allModels {
      modelsByKey[model.id] = model
    }

    // Compute per-podcast aggregates for UpNextSuggestionEngine signals
    var podcastPlayCounts: [String: Int] = [:]
    var podcastRecentPlayDates: [String: Date] = [:]
    for model in allModels {
      podcastPlayCounts[model.podcastTitle, default: 0] += model.playCount
      if let d = model.lastPlayedDate {
        if let existing = podcastRecentPlayDates[model.podcastTitle] {
          if d > existing { podcastRecentPlayDates[model.podcastTitle] = d }
        } else {
          podcastRecentPlayDates[model.podcastTitle] = d
        }
      }
    }

    // Build EpisodeInput candidates (unplayed, up to 10 per podcast)
    var inputs: [EpisodeInput] = []

    for podcastModel in podcastInfoModelList {
      let podcastTitle = podcastModel.podcastInfo.title
      var unstartedCount = 0
      let maxUnstarted = 10

      for episode in podcastModel.podcastInfo.episodes {
        let key = Self.makeEpisodeKey(podcastTitle: podcastTitle, episodeTitle: episode.title)
        let model = modelsByKey[key]

        guard model?.isCompleted != true else { continue }

        let inProgress = Self.isEpisodeInProgress(model: model)
        if !inProgress {
          guard unstartedCount < maxUnstarted else { continue }
          unstartedCount += 1
        }

        let libraryEpisode = LibraryEpisode(
          id: key,
          podcastTitle: podcastTitle,
          imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
          language: podcastModel.podcastInfo.language,
          episodeInfo: episode,
          isStarred: model?.isStarred ?? false,
          isDownloaded: Self.hasLocalAudioFile(model?.localAudioPath),
          isCompleted: model?.isCompleted ?? false,
          lastPlaybackPosition: model?.lastPlaybackPosition ?? 0,
          savedDuration: model?.duration ?? 0
        )

        inputs.append(EpisodeInput(
          episode: libraryEpisode,
          downloadModel: model,
          podcastTotalPlayCount: podcastPlayCounts[podcastTitle] ?? 0,
          podcastMostRecentPlayDate: podcastRecentPlayDates[podcastTitle]
        ))
      }
    }

    // ── Score a large pool; the engine returns a single composite-ordered list ──
    let allScored = UpNextSuggestionEngine().score(inputs: inputs, limit: 50)
    var scoredByKey: [String: ScoredEpisode] = [:]
    for s in allScored { scoredByKey[s.id] = s }

    // Now-playing key (pinned to position 0 below).
    let currentEpisode = EnhancedAudioManager.shared.currentEpisode
    let currentKey: String? = currentEpisode.map {
      Self.makeEpisodeKey(podcastTitle: $0.podcastTitle, episodeTitle: $0.title)
    }

    // Apple-Podcasts-style flat ordering: take the engine's composite-sorted output,
    // exclude the current episode, and filter dismissed rows whose dismissal hasn't
    // been superseded by a later play (replaying resurfaces a removed episode).
    let flat = allScored.filter { scored in
      guard scored.episode.id != currentKey else { return false }
      guard let model = modelsByKey[scored.episode.id] else { return true }
      if let dismissed = model.upNextDismissedAt {
        let lastPlay = model.lastPlayedDate ?? .distantPast
        return dismissed <= lastPlay
      }
      return true
    }

    var result: [LibraryEpisode] = flat.map(\.episode)

    // ── Prepend Tier 1 ────────────────────────────────────────────────────────
    if let currentEpisode {
      let key = currentKey!
      let currentModel = modelsByKey[key]
      if currentModel?.isCompleted != true {
        result.removeAll { $0.id == key }
        let libraryEpisode: LibraryEpisode
        if let existing = scoredByKey[key]?.episode {
          libraryEpisode = existing
        } else {
          let episodeInfo = PodcastEpisodeInfo(
            title: currentEpisode.title,
            podcastEpisodeDescription: currentEpisode.episodeDescription,
            pubDate: currentEpisode.pubDate,
            audioURL: currentEpisode.audioURL,
            imageURL: currentEpisode.imageURL,
            duration: currentEpisode.duration,
            guid: currentEpisode.guid
          )
          libraryEpisode = LibraryEpisode(
            id: key,
            podcastTitle: currentEpisode.podcastTitle,
            imageURL: currentEpisode.imageURL,
            language: "",
            episodeInfo: episodeInfo,
            isStarred: currentModel?.isStarred ?? false,
            isDownloaded: Self.hasLocalAudioFile(currentModel?.localAudioPath),
            isCompleted: false,
            lastPlaybackPosition: currentModel?.lastPlaybackPosition ?? 0,
            savedDuration: currentModel?.duration ?? 0
          )
        }
        result.insert(libraryEpisode, at: 0)
        // Ensure the injected entry is scoreable by the view
        if scoredByKey[key] == nil {
          scoredByKey[key] = ScoredEpisode(
            episode: libraryEpisode, downloadModel: currentModel,
            score: .infinity, reason: .none, progressRatio: 0)
        }
      }
    }

    upNextEpisodes = result
    scoredUpNextEpisodes = result.compactMap { episode in
      if let existing = scoredByKey[episode.id] { return existing }
      return ScoredEpisode(episode: episode, downloadModel: modelsByKey[episode.id],
                           score: .infinity, reason: .none, progressRatio: 0)
    }
    let inProgressCount = scoredUpNextEpisodes.reduce(into: 0) { count, scored in
      if case .inProgress = scored.reason { count += 1 }
    }
    logger.info("Loaded \(self.upNextEpisodes.count) up-next episodes (inProgress=\(inProgressCount))")

    // Populate auto-play candidates from up next episodes, excluding the currently playing episode
    let currentPlayingId = EnhancedAudioManager.shared.currentEpisode?.id
    let autoPlayEpisodes = upNextEpisodes.compactMap { episode -> PlaybackEpisode? in
      guard episode.id != currentPlayingId else { return nil }
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
    // Replace (not append) so the scored Up Next order is authoritative
    EnhancedAudioManager.shared.updateAutoPlayCandidates(autoPlayEpisodes)
  }

  private static func makeEpisodeKey(podcastTitle: String, episodeTitle: String) -> String {
    "\(podcastTitle)\(episodeKeyDelimiter)\(episodeTitle)"
  }

  // MARK: - Episode Actions

  /// Play an episode - delegate to audio manager
  func playEpisode(_ episode: LibraryEpisode) {
    let audioURL = episode.episodeInfo.audioURL ?? ""
    let playbackEpisode = PlaybackEpisode(
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
    let startTime = episode.isCompleted ? 0 : episode.lastPlaybackPosition
    EnhancedAudioManager.shared.play(
      episode: playbackEpisode,
      audioURL: audioURL,
      startTime: startTime,
      imageURL: episode.imageURL,
      useDefaultSpeed: startTime == 0
    )
  }

  /// Mark episode as played and remove from Up Next
  func markAsPlayed(_ episode: LibraryEpisode) {
    guard let context = modelContext else { return }

    let key = Self.makeEpisodeKey(podcastTitle: episode.podcastTitle, episodeTitle: episode.episodeInfo.title)
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )

    if let model = try? context.fetch(descriptor).first {
      model.isCompleted = true
      model.lastPlaybackPosition = 0
      try? context.save()
    } else {
      // Create new model if doesn't exist
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: episode.episodeInfo.audioURL ?? "",
        isCompleted: true,
        imageURL: episode.imageURL,
        pubDate: episode.episodeInfo.pubDate
      )
      context.insert(model)
      try? context.save()
    }
    // Post notification — the completion observer will reload Up Next
    NotificationCenter.default.post(name: .episodeCompletionChanged, object: nil)
  }

  /// Hide an episode from Up Next without marking it played (Apple Podcasts "Remove" semantics).
  /// Replaying the episode resurfaces it because `lastPlayedDate` overtakes `upNextDismissedAt`.
  func dismissFromUpNext(_ episode: LibraryEpisode) {
    guard let context = modelContext else { return }

    let key = Self.makeEpisodeKey(podcastTitle: episode.podcastTitle, episodeTitle: episode.episodeInfo.title)
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )

    if let model = try? context.fetch(descriptor).first {
      model.upNextDismissedAt = Date()
    } else {
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: episode.episodeInfo.audioURL ?? "",
        imageURL: episode.imageURL,
        pubDate: episode.episodeInfo.pubDate,
        upNextDismissedAt: Date()
      )
      context.insert(model)
    }
    try? context.save()
    NotificationCenter.default.post(name: .episodeCompletionChanged, object: nil)
  }

  // MARK: - Load Top Podcasts

  private func loadTopPodcasts(forceRefresh: Bool = false) async {
    let regionToLoad = selectedRegion

    // Use cached data if available for this region (unless force refresh)
    if !forceRefresh && !Self.cachedTopPodcasts.isEmpty && Self.cachedRegion == regionToLoad {
      // Sync instance property from cache (for UI updates)
      if topPodcasts.isEmpty {
        topPodcasts = Self.cachedTopPodcasts
      }
      // Restore the freshness timestamp from disk if a new instance is reusing the
      // in-memory cache without having stamped it yet.
      if popularShowsFetchedAt == nil {
        popularShowsFetchedAt = DiscoveryCacheStore.loadTopPodcasts(region: regionToLoad)?.fetchedAt
      }
      displayedRegion = regionToLoad
      logger.debug("Using cached top podcasts for \(regionToLoad)")
      return
    }

    // Join existing task if it matches our region (prevents duplicate requests)
    if let task = Self.loadingTask, Self.loadingRegion == regionToLoad {
      isLoadingTopPodcasts = true
      do {
        let podcasts = try await task.value
        if selectedRegion == regionToLoad {
          topPodcasts = podcasts
          displayedRegion = regionToLoad
          popularShowsFetchedAt = Date()
          hasFreshPopularShowsThisSession = true
        }
      } catch {
        logger.error("Joined task failed: \(error.localizedDescription, privacy: .public)")
      }
      isLoadingTopPodcasts = false
      return
    }

    // Start new task
    logger.info("Starting new top podcasts load for \(regionToLoad)")
    isLoadingTopPodcasts = true
    Self.loadingRegion = regionToLoad

    // Blank the list only when switching to a different region (old rows are for the
    // wrong region). For a same-region refresh — pull-to-refresh or reconnect — keep
    // the current list on screen and swap it when fresh data lands: no flash of empty.
    if let shown = displayedRegion, shown != regionToLoad {
      topPodcasts = []
      displayedRegion = nil
      Self.cachedTopPodcasts = []
      Self.cachedRegion = ""
    }

    // Create shared task with retry logic and limit fallback for API failures
    let task = Task { () -> [AppleRSSPodcast] in
      // Try with limit 200 first; some regions return 500 for high limits
      let limits = [200, 100, 50]
      var lastError: Error?
      for limit in limits {
        do {
          return try await applePodcastService.fetchTopPodcasts(region: regionToLoad, limit: limit)
        } catch {
          lastError = error
          let isServerError = (error as NSError).domain == NSURLErrorDomain ||
                              (error as? URLError)?.code == .badServerResponse
          if isServerError {
            logger.warning("Region \(regionToLoad) failed with limit \(limit), trying smaller: \(error.localizedDescription, privacy: .public)")
            try? await Task.sleep(for: .milliseconds(300))
            continue
          }
          throw error
        }
      }
      throw lastError ?? URLError(.unknown)
    }
    Self.loadingTask = task

    do {
      let podcasts = try await task.value
      // Update both static cache and observable instance property
      Self.cachedTopPodcasts = podcasts
      Self.cachedRegion = regionToLoad
      // Persist for offline browsing + an instant cold-launch paint next time.
      DiscoveryCacheStore.saveTopPodcasts(podcasts, region: regionToLoad)

      // Update instance property only if region hasn't changed
      if selectedRegion == regionToLoad {
        topPodcasts = podcasts
        displayedRegion = regionToLoad
        popularShowsFetchedAt = Date()
        hasFreshPopularShowsThisSession = true
      }
      logger.info("Loaded \(podcasts.count) top podcasts for \(regionToLoad)")
    } catch {
      logger.error("Failed to load top podcasts: \(error.localizedDescription, privacy: .public)")
    }

    // Cleanup static state if it's still ours
    if Self.loadingRegion == regionToLoad {
      Self.loadingRegion = nil
      Self.loadingTask = nil
    }

    isLoadingTopPodcasts = false
  }

  /// Paint Popular Shows from the on-disk cache when we have nothing to show yet.
  /// Cheap, synchronous, best-effort — gives an instant first frame on cold launch and
  /// keeps the tab browsable with no internet. No-op once `topPodcasts` is populated
  /// (live data always wins).
  private func hydratePopularShowsFromDisk() {
    guard topPodcasts.isEmpty,
          let cached = DiscoveryCacheStore.loadTopPodcasts(region: selectedRegion) else { return }
    topPodcasts = cached.podcasts
    popularShowsFetchedAt = cached.fetchedAt
    displayedRegion = selectedRegion
    // Deliberately NOT writing the static in-memory cache here: that flag means
    // "fetched from network this session" and gates the launch refresh. Disk data is
    // from a previous session, so we still want a fresh fetch to run and swap in.
    logger.debug("Hydrated \(cached.podcasts.count) popular shows from disk for \(self.selectedRegion)")
  }

  /// Check if a podcast is already subscribed by name
  func isAlreadySubscribed(_ podcast: AppleRSSPodcast) -> Bool {
    podcastInfoModelList.contains { $0.podcastInfo.title == podcast.name }
  }

  // MARK: - Subscribe to Podcast

  func subscribeToPodcast(_ podcast: AppleRSSPodcast) {
    guard let context = modelContext else { return }

    subscribeTask?.cancel()
    subscribeTask = Task {
      do {
        guard let result = try await applePodcastService.lookupPodcast(collectionId: podcast.id),
              let feedUrl = result.feedUrl else {
          logger.error("Could not find RSS feed for \(podcast.name)")
          return
        }

        let podcastInfo = try await rssService.fetchPodcast(from: feedUrl)

        if let existingByRSS = try? context.fetch(FetchDescriptor<PodcastInfoModel>(
          predicate: #Predicate { $0.rssUrl == feedUrl }
        )).first {
          existingByRSS.isSubscribed = true
          existingByRSS.applyPodcastInfo(podcastInfo)
          existingByRSS.lastUpdated = Date()
          try context.save()
          await loadUpNextEpisodes()
          logger.info("Reused existing podcast row for \(podcastInfo.title)")
          return
        }

        let title = podcastInfo.title
        if let existingByTitle = try? context.fetch(FetchDescriptor<PodcastInfoModel>(
          predicate: #Predicate { $0.title == title }
        )).first {
          existingByTitle.isSubscribed = true
          existingByTitle.applyPodcastInfo(podcastInfo)
          existingByTitle.lastUpdated = Date()
          try context.save()
          await loadUpNextEpisodes()
          logger.info("Reused title-matched podcast row for \(podcastInfo.title)")
          return
        }

        let model = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date(), isSubscribed: true)
        context.insert(model)
        try context.save()
        podcastInfoModelList.insert(model, at: 0)
        await loadUpNextEpisodes()
        logger.info("Successfully subscribed to \(podcastInfo.title)")
      } catch {
        logger.error("Failed to subscribe: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  // MARK: - For You Recommendations

  @available(iOS 26.0, macOS 26.0, *)
  func refreshRecommendations() {
    recommendedEpisodes = []
    loadRecommendations()
  }

  @available(iOS 26.0, macOS 26.0, *)
  func loadRecommendations() {
    guard !isLoadingRecommendations else { return }
    guard showForYouRecommendations else {
      recommendedEpisodes = []
      return
    }
    guard let context = modelContext else { return }

    recommendationsTask?.cancel()
    isLoadingRecommendations = true

    recommendationsTask = Task { [weak self] in
      guard let self else { return }
      defer { isLoadingRecommendations = false }

      let service = AppleFoundationModelsService()
      guard await service.checkAvailability().isAvailable else { return }

      // Single fetch: feeds the listening-history signal, the completed-episode
      // filter, and the result-card hydration below — no second pass.
      let descriptor = FetchDescriptor<EpisodeDownloadModel>(
        sortBy: [SortDescriptor(\.lastPlayedDate, order: .reverse)]
      )
      guard let allModels = try? context.fetch(descriptor) else { return }
      var modelsByKey: [String: EpisodeDownloadModel] = [:]
      for model in allModels { modelsByKey[model.id] = model }

      let playedModels = allModels.filter { $0.playCount > 0 || $0.lastPlayedDate != nil }
      let listeningHistory = playedModels.prefix(10).map {
        (title: $0.episodeTitle, podcastTitle: $0.podcastTitle, completed: $0.isCompleted)
      }
      guard !listeningHistory.isEmpty else { return }

      // Ordered candidate list (recent, unplayed). Keep each episode + its
      // podcast so the model's chosen list numbers map straight back to real
      // episodes — no brittle title-string matching.
      var candidates: [(episode: PodcastEpisodeInfo, podcast: PodcastInfoModel)] = []
      for podcastModel in podcastInfoModelList {
        for episode in podcastModel.podcastInfo.episodes.prefix(5) {
          let key = Self.makeEpisodeKey(podcastTitle: podcastModel.podcastInfo.title, episodeTitle: episode.title)
          if modelsByKey[key]?.isCompleted != true {
            candidates.append((episode, podcastModel))
          }
        }
      }
      let limited = Array(candidates.prefix(15))
      guard !limited.isEmpty else { return }

      let availableEpisodes = limited.map {
        (title: $0.episode.title,
         podcastTitle: $0.podcast.podcastInfo.title,
         description: $0.episode.podcastEpisodeDescription ?? "")
      }

      guard !Task.isCancelled else { return }

      do {
        let result = try await service.generateEpisodeRecommendations(
          listeningHistory: listeningHistory,
          availableEpisodes: availableEpisodes
        )
        guard !Task.isCancelled else { return }
        recommendedEpisodes = Self.buildRecommendedEpisodes(
          from: result.recommendedNumbers, candidates: limited, modelsByKey: modelsByKey)
      } catch {
        logger.error("Failed to generate recommendations: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// Maps the model's 1-based list numbers back to real episodes, skipping
  /// out-of-range or duplicate picks. Index-based, so a paraphrased or
  /// truncated title can't silently drop a recommendation.
  private static func buildRecommendedEpisodes(
    from numbers: [Int],
    candidates: [(episode: PodcastEpisodeInfo, podcast: PodcastInfoModel)],
    modelsByKey: [String: EpisodeDownloadModel]
  ) -> [LibraryEpisode] {
    var resolved: [LibraryEpisode] = []
    var seen = Set<Int>()
    for number in numbers {
      let index = number - 1  // the model is shown a 1-based list
      guard candidates.indices.contains(index), seen.insert(index).inserted else { continue }
      let (episode, podcastModel) = candidates[index]
      let key = makeEpisodeKey(podcastTitle: podcastModel.podcastInfo.title, episodeTitle: episode.title)
      let model = modelsByKey[key]
      resolved.append(LibraryEpisode(
        id: key,
        podcastTitle: podcastModel.podcastInfo.title,
        imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
        language: podcastModel.podcastInfo.language,
        episodeInfo: episode,
        isStarred: model?.isStarred ?? false,
        isDownloaded: hasLocalAudioFile(model?.localAudioPath),
        isCompleted: model?.isCompleted ?? false,
        lastPlaybackPosition: model?.lastPlaybackPosition ?? 0,
        savedDuration: model?.duration ?? 0
      ))
    }
    return resolved
  }

  // MARK: - Trending Episodes

  private static var cachedTrendingEpisodes: [ApplePodcastService.TrendingEpisode] = []
  private static var cachedTrendingRegion: String = ""

  private func loadTrendingEpisodes(forceRefresh: Bool = false) async {
    let regionToLoad = selectedRegion

    // Use cache if available
    if !forceRefresh && !Self.cachedTrendingEpisodes.isEmpty && Self.cachedTrendingRegion == regionToLoad {
      if trendingEpisodes.isEmpty {
        trendingEpisodes = Self.cachedTrendingEpisodes
      }
      return
    }

    isLoadingTrendingEpisodes = true
    do {
      // Use first 10 from already-loaded topPodcasts (lightweight iTunes Lookup API)
      let podcastsToSample = Array(topPodcasts.prefix(10))
      guard !podcastsToSample.isEmpty else {
        logger.warning("No top podcasts available for trending episodes")
        isLoadingTrendingEpisodes = false
        return
      }
      let episodes = try await applePodcastService.fetchTrendingEpisodesFromLookup(
        topPodcasts: podcastsToSample,
        episodesPerPodcast: 2
      )
      Self.cachedTrendingEpisodes = episodes
      Self.cachedTrendingRegion = regionToLoad
      if selectedRegion == regionToLoad {
        trendingEpisodes = episodes
      }
      logger.info("Loaded \(episodes.count) trending episodes for \(regionToLoad)")
    } catch {
      logger.error("Failed to load trending episodes: \(error.localizedDescription, privacy: .public)")
    }
    isLoadingTrendingEpisodes = false
  }

  func cleanup() {
    isHomeVisible = false
    loadTask?.cancel()
    loadTask = nil
    regionObserverTask?.cancel()
    regionObserverTask = nil
    regionChangeTask?.cancel()
    regionChangeTask = nil
    recommendationsTask?.cancel()
    recommendationsTask = nil
    subscribeTask?.cancel()
    subscribeTask = nil
    completionObserverTask?.cancel()
    completionObserverTask = nil
    reconnectObserverTask?.cancel()
    reconnectObserverTask = nil
    syncObserverTask?.cancel()
    syncObserverTask = nil
  }

  // MARK: - Find Podcast Model

  func findPodcastModel(for podcastTitle: String) -> PodcastInfoModel? {
    podcastInfoModelList.first { $0.podcastInfo.title == podcastTitle }
  }

  // MARK: - Star/Unstar Episode

  func toggleStar(for episode: LibraryEpisode) {
    guard let context = modelContext else { return }

    let key = Self.makeEpisodeKey(podcastTitle: episode.podcastTitle, episodeTitle: episode.episodeInfo.title)
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )

    if let model = try? context.fetch(descriptor).first {
      model.isStarred.toggle()
      try? context.save()
    } else {
      // Create new model if doesn't exist
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: episode.episodeInfo.audioURL ?? "",
        isStarred: true,
        imageURL: episode.imageURL,
        pubDate: episode.episodeInfo.pubDate
      )
      context.insert(model)
      try? context.save()
    }
  }

  // MARK: - Mark Played/Unplayed Episode

  func togglePlayed(for episode: LibraryEpisode) {
    guard let context = modelContext else { return }

    let key = Self.makeEpisodeKey(podcastTitle: episode.podcastTitle, episodeTitle: episode.episodeInfo.title)
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )

    if let model = try? context.fetch(descriptor).first {
      model.isCompleted.toggle()
      model.lastPlaybackPosition = 0
      try? context.save()
    } else {
      // Create new model if doesn't exist
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: episode.episodeInfo.audioURL ?? "",
        isCompleted: true,
        imageURL: episode.imageURL,
        pubDate: episode.episodeInfo.pubDate
      )
      context.insert(model)
      try? context.save()
    }

    // Post notification — the completion observer will reload Up Next
    NotificationCenter.default.post(name: .episodeCompletionChanged, object: nil)
  }
}
