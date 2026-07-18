//
//  EpisodeListViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for EpisodeListView - handles filtering, sorting, and episode operations
//

import SwiftUI
import OSLog
import SwiftData
import ZMarkupParser

#if os(iOS)
import UIKit
#else
import AppKit
#endif


private let viewModelLogger = Logger(subsystem: "com.podcast.analyzer", category: "ViewModelLifecycle")

@MainActor
@Observable
final class EpisodeListViewModel {
  var episodeModels: [String: EpisodeDownloadModel] = [:] {
    didSet { recomputeFilteredEpisodes() }
  }

  #if DEBUG
  private let instanceId = UUID()
  #endif
  var selectedFilter: EpisodeFilter = .all {
    didSet {
      isShowingAllEpisodes = false  // collapse back to the window for the new set
      transcriptKeySnapshot = nil   // re-scan transcript presence when the chip is (re)selected
      recomputeFilteredEpisodes()
    }
  }
  var sortOldestFirst: Bool = false {
    didSet { recomputeFilteredEpisodes() }  // same set, just reordered — keep expansion
  }
  var searchText: String = "" {
    didSet {
      isShowingAllEpisodes = false
      recomputeFilteredEpisodes()
    }
  }
  var isRefreshing: Bool = false
  var isDescriptionExpanded: Bool = false

  enum DescriptionContent {
    case loading
    case empty
    case parsed(NSAttributedString)
  }

  // HTML-rendered description content
  var descriptionContent: DescriptionContent = .loading

  // MARK: - Dependencies
  private let podcastModel: PodcastInfoModel
  private let downloadManager = DownloadManager.shared
  private let rssService = PodcastRssService()
  private var modelContext: ModelContext?
  private var downloadCompletionObserver: NSObjectProtocol?
  private var parseDescriptionTask: Task<Void, Never>?
  @ObservationIgnored private var isCleaned = false
  @ObservationIgnored private var progressTimer: Timer?
  @ObservationIgnored private var lastRefreshDate: Date?

  // MARK: - Throttled Download States Snapshot
  //
  // PERFORMANCE: Exposing a throttled snapshot here means EpisodeRowView rows no
  // longer subscribe directly to DownloadManager.downloadStates. Instead, only
  // this ViewModel re-renders (once) when download progress changes significantly,
  // and the snapshot is passed to each row as a let constant — preventing cascade
  // re-renders of every visible row on every URLSession progress tick.

  /// Throttled snapshot of download states for episodes in this podcast.
  /// Updated at most once per 250 ms of aggregate progress, mirroring the
  /// throttle already applied in DownloadManager's URLSession delegate.
  private(set) var downloadStatesSnapshot: [String: DownloadState] = [:]

  /// Episode keys that have a transcript, scanned once when the Transcript
  /// filter is engaged (nil = not built / stale) via the same
  /// `EpisodeStatusChecker.hasTranscript` the row badge uses. Cached so search
  /// keystrokes don't re-query `TranscriptStore` for every visible episode.
  @ObservationIgnored private var transcriptKeySnapshot: Set<String>?

  // MARK: - Cached Filtered Episodes

  private(set) var filteredEpisodes: [PodcastEpisodeInfo] = []

  /// Episodes shown on first open before the user taps "Show All". Keeps
  /// navigating into a large feed light — only this many rows are materialized
  /// by the List initially, so first paint isn't proportional to a 600+ backlog.
  static let initialEpisodeDisplayCount = 10

  /// When false, only the first `initialEpisodeDisplayCount` filtered episodes
  /// render; the user reveals the rest via the "Show All" footer button. Reset
  /// whenever the filtered set changes (filter / search), kept across re-sorts.
  var isShowingAllEpisodes = false

  /// Cached decoded snapshot. Reading the model's stored podcast blob
  /// re-materializes the entire episode array out of SwiftData's backing store
  /// on every access, and this view touches it per row and inside filter loops —
  /// so we decode once (refreshed in init + refreshPodcast) and read this cheap
  /// cached struct everywhere else. This is what keeps a 600+ episode list fast.
  private(set) var podcastInfo: PodcastInfo

  /// Episodes actually rendered by the List — a capped window until "Show All".
  var displayedEpisodes: [PodcastEpisodeInfo] {
    isShowingAllEpisodes
      ? filteredEpisodes
      : Array(filteredEpisodes.prefix(Self.initialEpisodeDisplayCount))
  }

  /// True when more episodes exist beyond the initial window.
  var hasMoreEpisodesToShow: Bool {
    !isShowingAllEpisodes && filteredEpisodes.count > Self.initialEpisodeDisplayCount
  }

  /// Episode keys with a transcript `.srt` on disk. Scanned once per Transcript-
  /// filter engagement via the same `EpisodeStatusChecker` the row badge uses,
  /// then cached so repeated recomputes (e.g. search keystrokes) don't re-hit
  /// the filesystem.
  // ponytail: O(N) fileExists once per engagement; swap to a single directory
  // scan if a feed ever has enough episodes to make this drag.
  private func episodeKeysWithTranscript() -> Set<String> {
    if let cached = transcriptKeySnapshot { return cached }
    var keys: Set<String> = []
    for episode in podcastInfo.episodes {
      let checker = EpisodeStatusChecker(episode: episode, podcastTitle: podcastInfo.title)
      if checker.hasTranscript { keys.insert(makeEpisodeKey(episode)) }
    }
    transcriptKeySnapshot = keys
    return keys
  }

  private func recomputeFilteredEpisodes() {
    var episodes = podcastInfo.episodes

    // Apply search filter first
    if !searchText.isEmpty {
      let query = searchText
      episodes = episodes.filter { episode in
        episode.title.localizedStandardContains(query)
          || (episode.podcastEpisodeDescription?.localizedStandardContains(query) ?? false)
      }
    }

    // Apply category filter
    switch selectedFilter {
    case .all:
      break
    case .unplayed:
      episodes = episodes.filter { episode in
        let key = makeEpisodeKey(episode)
        guard let model = episodeModels[key] else { return true }
        return !model.isCompleted && model.progress < 0.1
      }
    case .played:
      episodes = episodes.filter { episode in
        let key = makeEpisodeKey(episode)
        guard let model = episodeModels[key] else { return false }
        return model.isCompleted
      }
    case .starred:
      episodes = episodes.filter { episode in
        let key = makeEpisodeKey(episode)
        guard let model = episodeModels[key] else { return false }
        return model.isStarred
      }
    case .downloaded:
      episodes = episodes.filter { episode in
        let state = downloadManager.getDownloadState(
          episodeTitle: episode.title,
          podcastTitle: podcastInfo.title
        )
        if case .downloaded = state { return true }
        return false
      }
    case .transcript:
      let withTranscript = episodeKeysWithTranscript()
      episodes = episodes.filter { episode in
        // RSS-advertised transcript (downloadable on demand).
        if let url = episode.transcriptURL, !url.isEmpty { return true }
        // A generated/fetched .srt exists on disk — same source of truth as the
        // row's transcript badge.
        return withTranscript.contains(makeEpisodeKey(episode))
      }
    case .custom:
      // Reuses the auto-download evaluator — same include/exclude/min-duration
      // semantics, so the chip surfaces exactly the set that auto-download
      // would pick. Falls through to "show all" when no filter fields are set,
      // matching the evaluator's "no filters = accept" behavior.
      let include = podcastModel.episodeFilterInclude
      let exclude = podcastModel.episodeFilterExclude
      let minDur = podcastModel.episodeFilterMinDuration
      episodes = episodes.filter { episode in
        EpisodeFilterEvaluator.shouldAutoDownload(
          episodeTitle: episode.title,
          durationSeconds: TimeInterval(episode.duration ?? 0),
          includeFilter: include,
          excludeFilter: exclude,
          minDurationSeconds: minDur
        )
      }
    }

    // Apply sort
    if sortOldestFirst {
      episodes = episodes.sorted { (e1, e2) in
        guard let d1 = e1.pubDate, let d2 = e2.pubDate else { return false }
        return d1 < d2
      }
    }

    filteredEpisodes = episodes
  }

  // MARK: - Initialization

  init(podcastModel: PodcastInfoModel, initialFilter: EpisodeFilter = .all) {
    self.podcastModel = podcastModel
    self.podcastInfo = podcastModel.podcastInfo  // decode once; cached for every read below
    self.selectedFilter = initialFilter
    recomputeFilteredEpisodes()
    parseDescription()
    observeDownloadStates()
    manageProgressTimer()
    #if DEBUG
    viewModelLogger.info("📦 EpisodeListViewModel INIT: \(self.instanceId) for \(self.podcastInfo.title)")
    #endif
  }

  // MARK: - Download State Observation

  /// Observe DownloadManager.downloadStates with an early-exit guard:
  /// only rebuild the snapshot when there's a meaningful change for
  /// episodes belonging to this podcast. This prevents every EpisodeRowView
  /// from re-rendering on each URLSession progress callback.
  private func observeDownloadStates() {
    guard !isCleaned else { return }

    withObservationTracking {
      // Subscribe to state transitions only (start/finish/fail/cancel).
      // Progress updates now go to inFlightProgress (non-observable),
      // so this callback fires only on actual state changes.
      _ = downloadManager.downloadStates
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self, !self.isCleaned else { return }
        self.rebuildDownloadStatesSnapshot()
        self.manageProgressTimer()
        self.observeDownloadStates()
      }
    }
  }

  private func rebuildDownloadStatesSnapshot() {
    let podcastTitle = podcastInfo.title
    var snapshot: [String: DownloadState] = [:]
    for (key, state) in downloadManager.downloadStates {
      guard key.hasPrefix(podcastTitle) else { continue }
      switch state {
      case .downloading:
        // Use latest progress from non-observable storage
        let progress = downloadManager.inFlightProgress[key] ?? 0
        snapshot[key] = .downloading(progress: progress)
      case .finishing:
        snapshot[key] = .finishing
      case .downloaded(let path):
        snapshot[key] = .downloaded(localPath: path)
      case .failed, .notDownloaded:
        snapshot[key] = state
      }
    }
    if snapshot != downloadStatesSnapshot {
      downloadStatesSnapshot = snapshot
    }
  }

  // MARK: - Progress Timer

  private func manageProgressTimer() {
    if downloadManager.hasActiveDownloads {
      guard progressTimer == nil else { return }
      progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.updateProgressFromInFlight()
        }
      }
    } else {
      progressTimer?.invalidate()
      progressTimer = nil
    }
  }

  /// Poll inFlightProgress and update the snapshot for actively downloading episodes.
  private func updateProgressFromInFlight() {
    guard !isCleaned else {
      progressTimer?.invalidate()
      progressTimer = nil
      return
    }
    let podcastTitle = podcastInfo.title
    var snapshot = downloadStatesSnapshot
    var changed = false
    for (key, progress) in downloadManager.inFlightProgress {
      guard key.hasPrefix(podcastTitle) else { continue }
      if case .downloading(let oldP) = snapshot[key] {
        if abs(oldP - progress) >= 0.01 {
          snapshot[key] = .downloading(progress: progress)
          changed = true
        }
      } else if snapshot[key] == nil {
        snapshot[key] = .downloading(progress: progress)
        changed = true
      }
    }
    if changed {
      downloadStatesSnapshot = snapshot
    }
    // Stop timer if no more active downloads
    if !downloadManager.hasActiveDownloads {
      progressTimer?.invalidate()
      progressTimer = nil
    }
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    loadEpisodeModels()
    setupDownloadCompletionObserver()
  }

  private func setupDownloadCompletionObserver() {
    // Remove existing observer if any
    if let observer = downloadCompletionObserver {
      NotificationCenter.default.removeObserver(observer)
    }

    // Capture podcast title before closure to avoid main actor isolation issues
    let myPodcastTitle = podcastInfo.title

    // Listen for download completion to update SwiftData
    downloadCompletionObserver = NotificationCenter.default.addObserver(
      forName: .episodeDownloadCompleted,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let self = self,
            let userInfo = notification.userInfo,
            let episodeTitle = userInfo["episodeTitle"] as? String,
            let podcastTitle = userInfo["podcastTitle"] as? String,
            let localPath = userInfo["localPath"] as? String else { return }

      // Only handle if this is for our podcast
      guard podcastTitle == myPodcastTitle else { return }

      // Dispatch to MainActor for the update (handler registered on .main but closure is non-isolated)
      Task { @MainActor in
        self.updateEpisodeDownloadModel(
          episodeTitle: episodeTitle,
          podcastTitle: podcastTitle,
          localPath: localPath
        )
      }
    }
  }

  private func updateEpisodeDownloadModel(episodeTitle: String, podcastTitle: String, localPath: String) {
    guard let context = modelContext else { return }

    let episodeKey = EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episodeTitle)

    // Check if model already exists
    if let existingModel = episodeModels[episodeKey] {
      existingModel.localAudioPath = localPath
      existingModel.downloadedDate = Date()
      // Get file size
      if let attrs = try? FileManager.default.attributesOfItem(atPath: localPath),
         let size = attrs[.size] as? Int64 {
        existingModel.fileSize = size
      }
      try? context.save()
    } else {
      // Find the episode to get its audio URL
      guard let episode = podcastInfo.episodes.first(where: { $0.title == episodeTitle }),
            let audioURL = episode.audioURL else { return }

      // Create new model
      let model = EpisodeDownloadModel(
        episodeTitle: episodeTitle,
        podcastTitle: podcastTitle,
        audioURL: audioURL,
        localAudioPath: localPath,
        downloadedDate: Date(),
        imageURL: episode.imageURL ?? podcastInfo.imageURL,
        pubDate: episode.pubDate
      )
      // Get file size
      if let attrs = try? FileManager.default.attributesOfItem(atPath: localPath),
         let size = attrs[.size] as? Int64 {
        model.fileSize = size
      }
      context.insert(model)
      try? context.save()
      episodeModels[episodeKey] = model
    }
  }

  // MARK: - HTML Description Parsing

  private func parseDescription() {
    let html = podcastInfo.podcastInfoDescription ?? ""

    guard !html.isEmpty else {
      descriptionContent = .empty
      return
    }

    let cacheKey = NSString(string: "\(html.hashValue)_13")
    if let cached = descriptionCache.object(forKey: cacheKey) {
      descriptionContent = .parsed(cached)
      return
    }

    #if os(iOS)
    let labelColor = UIColor.secondaryLabel
    #else
    let labelColor = NSColor.secondaryLabelColor
    #endif

    let rootStyle = MarkupStyle(
      font: MarkupStyleFont(size: 13),  // Smaller font for list view
      foregroundColor: MarkupStyleColor(color: labelColor)
    )

    let parser = ZHTMLParserBuilder.initWithDefault()
      .set(rootStyle: rootStyle)
      .build()

    parseDescriptionTask?.cancel()
    parseDescriptionTask = Task {
      let attributedString = parser.render(html)
      guard !Task.isCancelled else { return }
      descriptionCache.setObject(attributedString, forKey: cacheKey)
      self.descriptionContent = .parsed(attributedString)
    }
  }

  // MARK: - Episode Key Helper

  func makeEpisodeKey(_ episode: PodcastEpisodeInfo) -> String {
    EpisodeKeyUtils.makeKey(podcastTitle: podcastInfo.title, episodeTitle: episode.title)
  }

  // MARK: - Data Loading

  func loadEpisodeModels() {
    guard let context = modelContext else { return }

    let podcastTitle = podcastInfo.title
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.podcastTitle == podcastTitle }
    )

    do {
      let results = try context.fetch(descriptor)
      var models: [String: EpisodeDownloadModel] = [:]
      for model in results {
        models[model.id] = model
      }
      episodeModels = models
    } catch {
      viewModelLogger.error("Failed to load episode models: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Podcast Operations

  func refreshPodcast() async {
    // Skip network fetch if refreshed within last 30 minutes
    let staleAfter: TimeInterval = 30 * 60
    if let last = lastRefreshDate, Date().timeIntervalSince(last) < staleAfter {
      return
    }
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      let updatedPodcast = try await rssService.fetchPodcast(
        from: podcastInfo.rssUrl)
      // Merge instead of replace: episodes with user data that aged off the RSS feed
      // (downloaded, starred, played, or in-progress) are preserved.
      let preservedKeys: Set<String> = Set(
        episodeModels
          .filter { _, model in
            model.localAudioPath != nil || model.isStarred || model.isCompleted
              || model.lastPlaybackPosition > 0 || model.playCount > 0
          }
          .map { key, _ in key }
      )
      let merged = podcastInfo.merging(
        updatedFrom: updatedPodcast, preservedKeys: preservedKeys)
      podcastModel.applyPodcastInfo(merged)
      podcastInfo = merged  // refresh the cache from the value we just built (no re-decode)
      transcriptKeySnapshot = nil  // episodes changed — re-scan transcript presence on next use
      recomputeFilteredEpisodes()
      try? modelContext?.save()
      lastRefreshDate = Date()
    } catch {
      viewModelLogger.error("Failed to refresh podcast: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Episode Actions

  /// Returns the existing download model for `episode`, or creates, inserts, and
  /// caches a fresh one. nil only when there's no model context or the episode
  /// has no audio URL. Callers mutate the result and save.
  @discardableResult
  private func ensureModel(for episode: PodcastEpisodeInfo) -> EpisodeDownloadModel? {
    let key = makeEpisodeKey(episode)
    if let existing = episodeModels[key] { return existing }
    guard let context = modelContext, let audioURL = episode.audioURL else { return nil }
    let model = EpisodeDownloadModel(
      episodeTitle: episode.title,
      podcastTitle: podcastInfo.title,
      audioURL: audioURL,
      imageURL: episode.imageURL ?? podcastInfo.imageURL,
      pubDate: episode.pubDate
    )
    context.insert(model)
    episodeModels[key] = model
    return model
  }

  func toggleStar(for episode: PodcastEpisodeInfo) {
    guard let model = ensureModel(for: episode) else { return }
    model.isStarred.toggle()
    try? modelContext?.save()
  }

  func downloadEpisode(_ episode: PodcastEpisodeInfo) {
    downloadManager.downloadEpisode(
      episode: episode,
      podcastTitle: podcastInfo.title,
      language: podcastInfo.language
    )
  }

  func deleteDownload(_ episode: PodcastEpisodeInfo) {
    downloadManager.deleteDownload(
      episodeTitle: episode.title,
      podcastTitle: podcastInfo.title
    )
  }

  func togglePlayed(for episode: PodcastEpisodeInfo) {
    guard let model = ensureModel(for: episode) else { return }
    model.isCompleted.toggle()
    model.lastPlaybackPosition = 0
    try? modelContext?.save()
  }

  // MARK: - Cleanup

  /// Clean up all resources to prevent memory leaks
  func cleanup() {
    #if DEBUG
    viewModelLogger.info("🗑️ EpisodeListViewModel CLEANUP: \(self.instanceId)")
    #endif
    isCleaned = true
    progressTimer?.invalidate()
    progressTimer = nil
    if let observer = downloadCompletionObserver {
      NotificationCenter.default.removeObserver(observer)
      downloadCompletionObserver = nil
    }
    parseDescriptionTask?.cancel()
    parseDescriptionTask = nil
  }
}
