//
//  HomeViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for Home tab - manages Up Next episodes and Popular Shows from Apple
//

import Foundation
import Observation
import SwiftData
import SwiftUI
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
  var recommendations: EpisodeRecommendations?
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
    let position = model.lastPlaybackPosition
    let duration = model.duration
    if duration > 0 {
      return position / duration > UpNextSuggestionEngine.inProgressMinRatio
    }
    return position > UpNextSuggestionEngine.inProgressMinSeconds
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
    // Restore saved region preference
    if let saved = UserDefaults.standard.string(forKey: "selectedPodcastRegion") {
      selectedRegion = saved
    }

    // Restore from static cache if available for current region
    if !Self.cachedTopPodcasts.isEmpty && Self.cachedRegion == selectedRegion {
      topPodcasts = Self.cachedTopPodcasts
    }

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
      logger.error("Failed to load podcasts: \(error.localizedDescription)")
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

    // ── Score a large pool so all tiers have enough candidates ─────────────
    let allScored = UpNextSuggestionEngine().score(inputs: inputs, limit: 50)
    var scoredByKey: [String: ScoredEpisode] = [:]
    for s in allScored { scoredByKey[s.id] = s }

    // ── Tier 1: currently playing (pinned to position 0) ────────────────────
    let currentEpisode = EnhancedAudioManager.shared.currentEpisode
    let currentKey: String? = currentEpisode.map {
      Self.makeEpisodeKey(podcastTitle: $0.podcastTitle, episodeTitle: $0.title)
    }

    // ── Tier 2: Continue Listening — in-progress episodes, newest-played first ─
    // Any episode whose scoring reason is .inProgress (position > threshold) and
    // is NOT the currently playing one lands here.  Sorted by lastPlayedDate DESC
    // so the episode you just switched away from always appears at position 1.
    var continueListening: [ScoredEpisode] = []

    // ── Tier 3: Suggestions — unstarted, highest score first ─────────────────
    var suggestions: [ScoredEpisode] = []

    for scored in allScored {
      guard scored.episode.id != currentKey else { continue }
      if case .inProgress = scored.reason {
        continueListening.append(scored)
      } else if suggestions.count < 15 {
        suggestions.append(scored)
      }
    }

    continueListening.sort {
      let aDate = modelsByKey[$0.episode.id]?.lastPlayedDate ?? .distantPast
      let bDate = modelsByKey[$1.episode.id]?.lastPlayedDate ?? .distantPast
      return aDate > bDate
    }

    // Build ordered list: Tier 2 → Tier 3 (Tier 1 prepended below)
    var result: [LibraryEpisode] = (continueListening + suggestions).map(\.episode)

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
    logger.info("Loaded \(self.upNextEpisodes.count) up-next episodes (continueListening=\(continueListening.count), suggestions=\(suggestions.count))")

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
    EnhancedAudioManager.shared.play(
      episode: playbackEpisode,
      audioURL: audioURL,
      startTime: episode.lastPlaybackPosition,
      imageURL: episode.imageURL,
      useDefaultSpeed: episode.lastPlaybackPosition == 0
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

  // MARK: - Load Top Podcasts

  private func loadTopPodcasts(forceRefresh: Bool = false) async {
    let regionToLoad = selectedRegion

    // Use cached data if available for this region (unless force refresh)
    if !forceRefresh && !Self.cachedTopPodcasts.isEmpty && Self.cachedRegion == regionToLoad {
      // Sync instance property from cache (for UI updates)
      if topPodcasts.isEmpty {
        topPodcasts = Self.cachedTopPodcasts
      }
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
        }
      } catch {
        logger.error("Joined task failed: \(error.localizedDescription)")
      }
      isLoadingTopPodcasts = false
      return
    }

    // Start new task
    logger.info("Starting new top podcasts load for \(regionToLoad)")
    isLoadingTopPodcasts = true
    Self.loadingRegion = regionToLoad

    // Clean up old data if force refreshing or changing region
    if forceRefresh || Self.cachedRegion != regionToLoad {
      topPodcasts = []
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
            logger.warning("Region \(regionToLoad) failed with limit \(limit), trying smaller: \(error.localizedDescription)")
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

      // Update instance property only if region hasn't changed
      if selectedRegion == regionToLoad {
        topPodcasts = podcasts
      }
      logger.info("Loaded \(podcasts.count) top podcasts for \(regionToLoad)")
    } catch {
      logger.error("Failed to load top podcasts: \(error.localizedDescription)")
    }

    // Cleanup static state if it's still ours
    if Self.loadingRegion == regionToLoad {
      Self.loadingRegion = nil
      Self.loadingTask = nil
    }

    isLoadingTopPodcasts = false
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
          existingByRSS.podcastInfo = podcastInfo
          existingByRSS.title = podcastInfo.title
          existingByRSS.rssUrl = podcastInfo.rssUrl
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
          existingByTitle.podcastInfo = podcastInfo
          existingByTitle.title = podcastInfo.title
          existingByTitle.rssUrl = podcastInfo.rssUrl
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
        logger.error("Failed to subscribe: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - For You Recommendations

  @available(iOS 26.0, macOS 26.0, *)
  func refreshRecommendations() {
    recommendations = nil
    recommendedEpisodes = []
    loadRecommendations()
  }

  @available(iOS 26.0, macOS 26.0, *)
  func loadRecommendations() {
    guard !isLoadingRecommendations else { return }

    // Check if For You is enabled
    guard UserDefaults.standard.object(forKey: "showForYouRecommendations") == nil ||
          UserDefaults.standard.bool(forKey: "showForYouRecommendations") else {
      recommendations = nil
      recommendedEpisodes = []
      return
    }

    guard let context = modelContext else { return }

    recommendationsTask?.cancel()
    isLoadingRecommendations = true

    recommendationsTask = Task { [weak self] in
      guard let self else { return }

      let service = AppleFoundationModelsService()
      let availability = await service.checkAvailability()
      guard availability.isAvailable else {
        isLoadingRecommendations = false
        return
      }

      // Query SwiftData for listening history
      let descriptor = FetchDescriptor<EpisodeDownloadModel>(
        sortBy: [SortDescriptor(\.lastPlayedDate, order: .reverse)]
      )

      guard let allModels = try? context.fetch(descriptor) else {
        isLoadingRecommendations = false
        return
      }

      let playedModels = allModels.filter { $0.playCount > 0 || $0.lastPlayedDate != nil }
      let listeningHistory: [(title: String, podcastTitle: String, completed: Bool)] = playedModels.prefix(10).map {
        (title: $0.episodeTitle, podcastTitle: $0.podcastTitle, completed: $0.isCompleted)
      }

      guard !listeningHistory.isEmpty else {
        isLoadingRecommendations = false
        return
      }

      // Build available episodes from subscribed podcasts (unplayed)
      // Reuse allModels already fetched above as a dictionary for O(1) lookup
      var modelsByKey: [String: EpisodeDownloadModel] = [:]
      for model in allModels {
        modelsByKey[model.id] = model
      }

      var availableEpisodes: [(title: String, podcastTitle: String, description: String)] = []
      for podcastModel in podcastInfoModelList {
        for episode in podcastModel.podcastInfo.episodes.prefix(5) {
          let key = Self.makeEpisodeKey(podcastTitle: podcastModel.podcastInfo.title, episodeTitle: episode.title)
          if modelsByKey[key]?.isCompleted != true {
            availableEpisodes.append((
              title: episode.title,
              podcastTitle: podcastModel.podcastInfo.title,
              description: episode.podcastEpisodeDescription ?? ""
            ))
          }
        }
      }

      let candidateEpisodes = Array(availableEpisodes.prefix(15))
      guard !candidateEpisodes.isEmpty else {
        isLoadingRecommendations = false
        return
      }

      if Task.isCancelled { isLoadingRecommendations = false; return }

      do {
        let result = try await service.generateEpisodeRecommendations(
          listeningHistory: listeningHistory,
          availableEpisodes: candidateEpisodes
        )
        if !Task.isCancelled {
          recommendations = result
          resolveRecommendedEpisodes()
        }
      } catch {
        logger.error("Failed to generate recommendations: \(error.localizedDescription)")
      }
      isLoadingRecommendations = false
    }
  }

  /// Match recommended titles against subscribed podcast episodes and build LibraryEpisode array
  private func resolveRecommendedEpisodes() {
    guard let recommendations, let context = modelContext else {
      recommendedEpisodes = []
      return
    }

    // Batch fetch all models once
    let allDescriptor = FetchDescriptor<EpisodeDownloadModel>()
    let allModels = (try? context.fetch(allDescriptor)) ?? []
    var modelsByKey: [String: EpisodeDownloadModel] = [:]
    for model in allModels {
      modelsByKey[model.id] = model
    }

    var resolved: [LibraryEpisode] = []
    for title in recommendations.recommendedTitles {
      // Search through subscribed podcasts for the episode
      for podcastModel in podcastInfoModelList {
        if let episode = podcastModel.podcastInfo.episodes.first(where: { $0.title == title }) {
          let key = Self.makeEpisodeKey(podcastTitle: podcastModel.podcastInfo.title, episodeTitle: episode.title)
          let model = modelsByKey[key]

          resolved.append(LibraryEpisode(
            id: key,
            podcastTitle: podcastModel.podcastInfo.title,
            imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
            language: podcastModel.podcastInfo.language,
            episodeInfo: episode,
            isStarred: model?.isStarred ?? false,
            isDownloaded: Self.hasLocalAudioFile(model?.localAudioPath),
            isCompleted: model?.isCompleted ?? false,
            lastPlaybackPosition: model?.lastPlaybackPosition ?? 0,
            savedDuration: model?.duration ?? 0
          ))
          break
        }
      }
    }
    recommendedEpisodes = resolved
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
      logger.error("Failed to load trending episodes: \(error.localizedDescription)")
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
