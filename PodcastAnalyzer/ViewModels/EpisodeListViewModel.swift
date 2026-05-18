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
    didSet { recomputeFilteredEpisodes() }
  }
  var sortOldestFirst: Bool = false {
    didSet { recomputeFilteredEpisodes() }
  }
  var searchText: String = "" {
    didSet { recomputeFilteredEpisodes() }
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

  // Use Unit Separator (U+001F) as delimiter - same as DownloadManager
  private static let episodeKeyDelimiter = "\u{1F}"

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

  // MARK: - Cached Filtered Episodes

  private(set) var filteredEpisodes: [PodcastEpisodeInfo] = []

  var podcastInfo: PodcastInfo {
    podcastModel.podcastInfo
  }

  var filteredEpisodeCount: Int {
    filteredEpisodes.count
  }

  private func recomputeFilteredEpisodes() {
    var episodes = podcastModel.podcastInfo.episodes

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
          podcastTitle: podcastModel.podcastInfo.title
        )
        if case .downloaded = state { return true }
        return false
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
    self.selectedFilter = initialFilter
    recomputeFilteredEpisodes()
    parseDescription()
    observeDownloadStates()
    manageProgressTimer()
    #if DEBUG
    viewModelLogger.info("📦 EpisodeListViewModel INIT: \(self.instanceId) for \(podcastModel.podcastInfo.title)")
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
    let podcastTitle = podcastModel.podcastInfo.title
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
    let podcastTitle = podcastModel.podcastInfo.title
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
    let myPodcastTitle = podcastModel.podcastInfo.title

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

    let episodeKey = "\(podcastTitle)\(Self.episodeKeyDelimiter)\(episodeTitle)"

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
      guard let episode = podcastModel.podcastInfo.episodes.first(where: { $0.title == episodeTitle }),
            let audioURL = episode.audioURL else { return }

      // Create new model
      let model = EpisodeDownloadModel(
        episodeTitle: episodeTitle,
        podcastTitle: podcastTitle,
        audioURL: audioURL,
        localAudioPath: localPath,
        downloadedDate: Date(),
        imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
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
    let html = podcastModel.podcastInfo.podcastInfoDescription ?? ""

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
    return "\(podcastModel.podcastInfo.title)\(Self.episodeKeyDelimiter)\(episode.title)"
  }

  // MARK: - Data Loading

  func loadEpisodeModels() {
    guard let context = modelContext else { return }

    let podcastTitle = podcastModel.podcastInfo.title
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
      print("Failed to load episode models: \(error)")
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
        from: podcastModel.podcastInfo.rssUrl)
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
      podcastModel.podcastInfo = podcastModel.podcastInfo.merging(
        updatedFrom: updatedPodcast, preservedKeys: preservedKeys)
      recomputeFilteredEpisodes()
      try? modelContext?.save()
      lastRefreshDate = Date()
    } catch {
      print("Failed to refresh podcast: \(error)")
    }
  }

  // MARK: - Episode Actions

  func toggleStar(for episode: PodcastEpisodeInfo) {
    guard let context = modelContext else { return }

    let key = makeEpisodeKey(episode)
    if let model = episodeModels[key] {
      model.isStarred.toggle()
      try? context.save()
    } else {
      guard let audioURL = episode.audioURL else { return }
      let model = EpisodeDownloadModel(
        episodeTitle: episode.title,
        podcastTitle: podcastModel.podcastInfo.title,
        audioURL: audioURL,
        imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
        pubDate: episode.pubDate
      )
      model.isStarred = true
      context.insert(model)
      try? context.save()
      episodeModels[key] = model
    }
  }

  func downloadEpisode(_ episode: PodcastEpisodeInfo) {
    downloadManager.downloadEpisode(
      episode: episode,
      podcastTitle: podcastModel.podcastInfo.title,
      language: podcastModel.podcastInfo.language
    )
  }

  func deleteDownload(_ episode: PodcastEpisodeInfo) {
    downloadManager.deleteDownload(
      episodeTitle: episode.title,
      podcastTitle: podcastModel.podcastInfo.title
    )
  }

  func togglePlayed(for episode: PodcastEpisodeInfo) {
    guard let context = modelContext else { return }

    let key = makeEpisodeKey(episode)
    if let model = episodeModels[key] {
      model.isCompleted.toggle()
      if !model.isCompleted {
        model.lastPlaybackPosition = 0
      }
      try? context.save()
    } else {
      guard let audioURL = episode.audioURL else { return }
      let model = EpisodeDownloadModel(
        episodeTitle: episode.title,
        podcastTitle: podcastModel.podcastInfo.title,
        audioURL: audioURL,
        imageURL: episode.imageURL ?? podcastModel.podcastInfo.imageURL,
        pubDate: episode.pubDate
      )
      model.isCompleted = true
      context.insert(model)
      try? context.save()
      episodeModels[key] = model
    }
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
