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
    // Only three filters read `episodeModels`, so only they can change membership
    // when it mutates. Recomputing unconditionally meant a star/played toggle on
    // an episode with no model yet (ensureModel inserts into this dict) re-filtered
    // and re-sorted the entire feed synchronously, while UIKit was still animating
    // the ellipsis menu away.
    didSet {
      switch selectedFilter {
      case .unplayed, .played, .starred: recomputeFilteredEpisodes()
      case .all, .downloaded, .transcript, .custom: break
      }
    }
  }

  #if DEBUG
  private let instanceId = UUID()
  #endif
  var selectedFilter: EpisodeFilter = .all {
    didSet {
      statusSnapshotsBuilt = false  // re-scan transcript presence when the chip is (re)selected
      recomputeFilteredEpisodes()
    }
  }
  var sortOldestFirst: Bool = false {
    didSet { recomputeFilteredEpisodes() }  // same set, just reordered
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
  // No `lastRefreshDate` here: a fresh view model is built on every push into
  // a show, so an instance-scoped throttle never fired and every open refetched
  // the feed. `podcastModel.lastUpdated` is the persistent record of when we
  // last saw it — and it also lets BackgroundSyncManager's sync suppress a
  // redundant fetch here.

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

  /// Episode keys with a stored transcript, and audio URLs with a stored AI
  /// analysis — both for *this* podcast, each built with a single fetch.
  ///
  /// These replace `EpisodeStatusChecker.hasTranscript` / `.hasAIAnalysis(in:)`
  /// being called per row. Both of those are SwiftData fetches (not the file
  /// checks their old comments claimed), so the previous shape cost two fetches
  /// for every row that appeared — twenty of them on the main thread during a
  /// push — and one fetch *per episode* when the Transcript filter was engaged.
  private(set) var transcriptKeys: Set<String> = []
  private(set) var aiAnalysisAudioURLs: Set<String> = []

  /// nil = not built / stale. Rebuilt on demand by `refreshStatusSnapshots`.
  @ObservationIgnored private var statusSnapshotsBuilt = false

  // MARK: - Cached Filtered Episodes

  private(set) var filteredEpisodes: [PodcastEpisodeInfo] = []

  /// Cached decoded snapshot. Reading the model's stored podcast blob
  /// re-materializes the entire episode array out of SwiftData's backing store
  /// on every access, and this view touches it per row and inside filter loops —
  /// so we decode once (refreshed in init + refreshPodcast) and read this cheap
  /// cached struct everywhere else. This is what keeps a 600+ episode list fast.
  private(set) var podcastInfo: PodcastInfo

  /// What the header's play button acts on: the episode the user last listened
  /// to in this show, falling back to the newest one when nothing here has been
  /// played yet. Independent of the chip filter and the sort direction.
  ///
  /// Recency is the later of `progressUpdatedAt` and `lastPlayedDate`. The
  /// first moves on every playback-position write, so it catches an episode
  /// left half-finished; the second only moves on completion, but legacy rows
  /// may carry just that one.
  ///
  /// Cached rather than computed in the view: it scans every episode and builds
  /// a key string for each one, and the header re-derived it on *every* body
  /// pass — including every download-progress tick.
  private(set) var playTarget: (episode: PodcastEpisodeInfo, isResume: Bool)?

  private func recomputePlayTarget() {
    let playable = podcastInfo.episodes.filter { $0.audioURL != nil }

    let lastListened =
      playable
      .compactMap { episode -> (PodcastEpisodeInfo, Date)? in
        guard let model = episodeModels[makeEpisodeKey(episode)],
          let stamp = [model.progressUpdatedAt, model.lastPlayedDate].compactMap({ $0 }).max()
        else { return nil }
        return (episode, stamp)
      }
      .max { $0.1 < $1.1 }?
      .0

    if let lastListened {
      playTarget = (lastListened, true)
      return
    }

    playTarget =
      playable
      .max { ($0.pubDate ?? .distantPast) < ($1.pubDate ?? .distantPast) }
      .map { ($0, false) }
  }

  /// Rebuild both status sets with one fetch each, scoped to this podcast.
  /// Idempotent — `statusSnapshotsBuilt` gates repeat work; callers that know
  /// the data moved (feed refresh, finished transcript) reset it first.
  func refreshStatusSnapshots() {
    guard let context = modelContext, !statusSnapshotsBuilt else { return }
    statusSnapshotsBuilt = true

    // EpisodeTranscriptModel is keyed only by `episodeId`, which is
    // "<podcastTitle>\u{1F}<episodeTitle>" — so a prefix match scopes it to
    // this podcast.
    let keyPrefix = podcastInfo.title + EpisodeKeyUtils.delimiter
    let transcriptDescriptor = FetchDescriptor<EpisodeTranscriptModel>(
      predicate: #Predicate { $0.episodeId.starts(with: keyPrefix) }
    )
    do {
      transcriptKeys = Set(try context.fetch(transcriptDescriptor).map(\.episodeId))
    } catch {
      // Don't swallow this: a predicate the store rejects would silently mean
      // "no episode has a transcript" rather than an obvious failure.
      viewModelLogger.error(
        "Transcript key fetch failed: \(error.localizedDescription, privacy: .public)")
      transcriptKeys = []
    }

    // `hasAnalysis` is computed, so it can't go in the predicate — fetch this
    // podcast's rows and apply the same test EpisodeStatusChecker used.
    let title = podcastInfo.title
    let analysisDescriptor = FetchDescriptor<EpisodeAIAnalysis>(
      predicate: #Predicate { $0.podcastTitle == title }
    )
    let analyses = (try? context.fetch(analysisDescriptor)) ?? []
    aiAnalysisAudioURLs = Set(
      analyses
        .filter { $0.hasAnalysis || !($0.qaHistoryJSON ?? "").isEmpty }
        .map(\.episodeAudioURL)
    )
  }

  /// Force the next `refreshStatusSnapshots()` to re-fetch.
  func invalidateStatusSnapshots() {
    statusSnapshotsBuilt = false
    refreshStatusSnapshots()
  }

  private func episodeKeysWithTranscript() -> Set<String> {
    refreshStatusSnapshots()
    return transcriptKeys
  }

  private func recomputeFilteredEpisodes() {
    var episodes = podcastInfo.episodes

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
    recomputePlayTarget()
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

    // Transcript / AI-analysis presence only feeds row badges — two more
    // main-thread SwiftData fetches that don't have to be in front of the first
    // frame. The Transcript chip needs them to filter at all, so re-run the
    // filter once they land.
    Task { [weak self] in
      await Task.yield()
      guard let self, !self.isCleaned else { return }
      self.refreshStatusSnapshots()
      if self.selectedFilter == .transcript {
        self.recomputeFilteredEpisodes()
      }
    }
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
      context.saveOrLog()
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
      context.saveOrLog()
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

    parseDescriptionTask?.cancel()
    parseDescriptionTask = Task {
      // Both the builder and `render` are main-actor work (ZMarkupParser isn't
      // Sendable, so neither can move off), and running them from `init` put a
      // full HTML parse of the show notes in front of the push animation's
      // first frame. Yield so the header paints first; the description arrives
      // into the space `.loading` already reserves.
      await Task.yield()
      guard !Task.isCancelled else { return }

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
      recomputePlayTarget()  // "Resume" vs "Latest" depends on these
    } catch {
      viewModelLogger.error("Failed to load episode models: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Podcast Operations

  /// - Parameter force: skip the staleness window. Pull-to-refresh and the
  ///   ••• menu's Refresh pass this: a gesture the user made explicitly should
  ///   always reach the feed, and with a conditional GET an unchanged one costs
  ///   a single 304.
  func refreshPodcast(force: Bool = false) async {
    // Otherwise skip the network fetch if this feed was seen within the last 30
    // minutes, by anyone — this view model or a background sync.
    let staleAfter: TimeInterval = 30 * 60
    if !force, Date.now.timeIntervalSince(podcastModel.lastUpdated) < staleAfter { return }
    isRefreshing = true
    defer { isRefreshing = false }

    do {
      // Conditional GET, same as BackgroundSyncManager: a feed that hasn't
      // published answers 304 and costs one round trip and no work at all. The
      // unconditional fetch this replaced re-parsed, re-merged, re-encoded and
      // re-saved the entire episode blob on the main actor every time the user
      // opened a show past the staleness window — for a large backlog that is
      // the multi-second stall that landed on top of the freshly-drawn list.
      let result = try await rssService.fetchPodcastConditional(
        from: podcastInfo.rssUrl, cacheHeader: podcastModel.httpCacheHeader)

      // Same bookkeeping BackgroundSyncManager does after a refresh: this is a
      // successful look at the feed, and the Library grid / macOS list treat
      // `lastUpdated` as "when we last saw this feed".
      podcastModel.lastUpdated = Date()

      guard case .updated(let updatedPodcast, let cacheHeader) = result else {
        modelContext?.saveOrLog()
        return
      }
      if let cacheHeader { podcastModel.httpCacheHeader = cacheHeader }

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

      // Feeds that serve no ETag still re-serve the same episodes, which is the
      // common case. Writing that back costs a whole-blob JSON encode plus a
      // SwiftData save proportional to the backlog — skip it unless something
      // the UI reads actually moved.
      guard changed(from: podcastInfo, to: merged) else {
        modelContext?.saveOrLog()
        return
      }

      podcastModel.applyPodcastInfo(merged)
      podcastInfo = merged  // refresh the cache from the value we just built (no re-decode)
      statusSnapshotsBuilt = false  // episodes changed — re-scan status on next use
      recomputeFilteredEpisodes()
      recomputePlayTarget()
      modelContext?.saveOrLog()
    } catch {
      viewModelLogger.error("Failed to refresh podcast: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Whether a merged snapshot differs from the one already on screen, by the
  /// fields this app renders. Episodes compare on the same identity the merge
  /// de-duplicates on, so a feed that only reworded a description is treated as
  /// unchanged — that is the point: the alternative is rewriting the blob.
  private func changed(from current: PodcastInfo, to merged: PodcastInfo) -> Bool {
    if merged.title != current.title { return true }
    if merged.imageURL != current.imageURL { return true }
    if merged.podcastInfoDescription != current.podcastInfoDescription { return true }
    if merged.episodes.count != current.episodes.count { return true }
    return zip(merged.episodes, current.episodes).contains { new, old in
      (new.guid ?? new.audioURL ?? new.title) != (old.guid ?? old.audioURL ?? old.title)
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
    // Pause before marking: see EnhancedAudioManager.pauseIfCurrent.
    if !model.isCompleted {
      EnhancedAudioManager.shared.pauseIfCurrent(episodeId: model.id)
    }
    model.setCompleted(!model.isCompleted)
    model.lastPlaybackPosition = 0
    modelContext?.saveOrLog()
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
