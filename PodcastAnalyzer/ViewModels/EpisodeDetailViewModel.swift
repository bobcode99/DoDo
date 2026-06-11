//
//  EpisodeDetailViewModel.swift
//  PodcastAnalyzer
//
//  Enhanced with download management and playback state
//

import SwiftUI
import Observation
import OSLog
import SwiftData
import ZMarkupParser

#if canImport(Translation)
@preconcurrency import Translation
#endif

#if os(iOS)
import UIKit
#else
import AppKit
#endif

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "EpisodeDetailViewModel")

/// Shared in-memory cache for parsed HTML descriptions.
/// Keyed by "\(html.hashValue)_\(fontSize)" to distinguish styles.
/// NSCache auto-evicts under memory pressure — no manual purging needed.
/// @MainActor because both ViewModels that use it are @MainActor-isolated.
@MainActor let descriptionCache: NSCache<NSString, NSAttributedString> = {
  let cache = NSCache<NSString, NSAttributedString>()
  cache.countLimit = 100
  cache.totalCostLimit = 50_000_000  // 50 MB
  return cache
}()

// MARK: - Transcript State

enum TranscriptState: Equatable {
  case idle
  case downloadingModel(progress: Double)
  case transcribing(progress: Double)
  case completed
  case error(String)
}

/// Represents word-level timing information for accurate highlighting
struct WordTiming: Equatable, Sendable {
  let word: String
  let startTime: TimeInterval
  let endTime: TimeInterval
}

/// Represents a single transcript segment with timing information
struct TranscriptSegment: Identifiable, Equatable {
  let id: Int
  let startTime: TimeInterval
  let endTime: TimeInterval
  let text: String
  var translatedText: String?
  /// Word-level timing for accurate highlighting (from Speech framework)
  var wordTimings: [WordTiming]?

  /// Formatted start time string (MM:SS or HH:MM:SS)
  var formattedStartTime: String {
    let totalSeconds = Int(startTime)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }

  /// Returns display text based on subtitle display mode
  func displayText(mode: SubtitleDisplayMode) -> (primary: String, secondary: String?) {
    switch mode {
    case .originalOnly:
      return (text, nil)
    case .translatedOnly:
      return (translatedText ?? text, nil)
    case .dualOriginalFirst:
      return (text, translatedText)
    case .dualTranslatedFirst:
      return (translatedText ?? text, translatedText != nil ? text : nil)
    }
  }

  /// Whether this segment has a translation
  var hasTranslation: Bool {
    translatedText != nil
  }
}

@MainActor @Observable
final class EpisodeDetailViewModel {

  // Pre-compiled SRT regex (compiled once, reused for every parse)
  private static let srtRegex: NSRegularExpression? = {
    let entryPattern =
      #"(?:^|\n)(\d+)\n(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})\n"#
    return try? NSRegularExpression(pattern: entryPattern, options: [])
  }()

  // Pre-compiled numeric HTML entity regex
  private static let numericEntityRegex: NSRegularExpression? = {
    return try? NSRegularExpression(pattern: "&#(\\d+);", options: [])
  }()

  enum DescriptionContent {
    case loading
    case empty
    case parsed(NSAttributedString)
  }

  var descriptionContent: DescriptionContent = .loading

  @ObservationIgnored
  let episode: PodcastEpisodeInfo

  @ObservationIgnored
  let podcastTitle: String

  @ObservationIgnored
  private let fallbackImageURL: String?

  // Reference singletons — NOT @ObservationIgnored so SwiftUI can observe through them
  let audioManager = EnhancedAudioManager.shared
  private let downloadManager = DownloadManager.shared

  // Download state (computed from @Observable DownloadManager)
  var downloadState: DownloadState {
    downloadManager.getDownloadState(
      episodeTitle: episode.title,
      podcastTitle: podcastTitle
    )
  }

  // Transcript state
  var transcriptState: TranscriptState = .idle
  var transcriptText: String = ""
  var isModelReady: Bool = false
  /// Language override for transcript generation.
  /// `nil` means use the engine default: podcast RSS language for Apple Speech,
  /// or auto-detect for Whisper.
  var selectedTranscriptLanguage: String?
  /// Engine override for transcript generation (nil = use global Settings default)
  var selectedTranscriptEngine: TranscriptEngine?
  /// Language detected by Whisper auto-detect during the current/last generation run.
  var transcriptDetectedLanguage: String?

  @ObservationIgnored
  private let fileStorage = FileStorageManager.shared

  // Parsed transcript segments — always the raw SRT entries (one segment per
  // SRT cue). Sentence-block grouping happens once in `regroupSentences()` and
  // is consumed via `groupedSentences` / `transcriptSentences`.
  var transcriptSegments: [TranscriptSegment] = []
  var transcriptSearchQuery: String = ""

  // Sentence grouping (precomputed, not per-render)
  var groupedSentences: [TranscriptSentence] = []

  // Search match navigation
  var searchMatchIds: [TranscriptSentence.ID] = []
  var currentMatchIndex: Int = 0

  // RSS transcript state (from podcast:transcript tag)
  var rssTranscriptState: TranscriptDownloadState = .notAvailable

  // DAI source tracking — computed from the live `EpisodeDownloadModel` below.

  // Translation state
  var translationStatus: TranslationStatus = .idle
  var translatedDescription: String?
  var translatedEpisodeTitle: String?
  var translatedPodcastTitle: String?  // Translated podcast show name
  var transcriptTranslationTrigger: Bool = false  // Toggle to trigger .translationTask
  var descriptionTranslationTrigger: Bool = false  // Toggle to trigger description translation
  var episodeTitleTranslationTrigger: Bool = false  // Toggle to trigger title translation
  var podcastTitleTranslationTrigger: Bool = false  // Toggle to trigger podcast title translation

  // Translation language selection
  var selectedTranslationLanguage: TranslationTargetLanguage?  // Language selected for translation
  var availableTranslationLanguages: Set<String> = []  // Cached language codes

  @ObservationIgnored
  private let translationService = TranslationService.shared

  @ObservationIgnored
  private let transcriptDownloadService = TranscriptDownloadService.shared

  @ObservationIgnored
  private let subtitleSettings = SubtitleSettingsManager.shared

  // Playback state from SwiftData. NOT @ObservationIgnored — once set,
  // reading `episodeModel?.<property>` in computed properties registers
  // Observation through both this view model and the @Model itself, so any
  // write by PlaybackStateCoordinator (same main context) re-renders the
  // detail view without a notification round-trip.
  private(set) var episodeModel: EpisodeDownloadModel?

  @ObservationIgnored
  private var modelContext: ModelContext?

  // Translation task for cancellation
  @ObservationIgnored
  private var translationTask: Task<Void, Never>?

  // Additional tracked tasks for proper cleanup
  @ObservationIgnored
  private var parseDescriptionTask: Task<Void, Never>?

  @ObservationIgnored
  private var checkTranscriptTask: Task<Void, Never>?

  @ObservationIgnored
  private var availableTranslationsTask: Task<Void, Never>?

  @ObservationIgnored
  private var loadTranscriptDateTask: Task<Void, Never>?

  @ObservationIgnored
  private var rssTranscriptCheckTask: Task<Void, Never>?

  @ObservationIgnored
  private var rssTranscriptDownloadTask: Task<Void, Never>?

  @ObservationIgnored
  private var loadExistingTranscriptTask: Task<Void, Never>?

  // Tasks for AI and playback operations
  @ObservationIgnored
  private var seekTask: Task<Void, Never>?

  /// AI lifecycle: on-device quick tags, cloud BYOK analysis + Q&A, and
  /// SwiftData persistence of both. Views read AI state through this child
  /// so @Observable invalidation stays scoped to AI updates.
  let aiAnalysis: AIAnalysisCoordinator

  // Flag to track transcript manager observation
  @ObservationIgnored
  private var isObservingTranscriptManager = false

  // Podcast language for transcription. Empty string means unknown — never use "en" as a default.
  var podcastLanguage: String = ""

  init(
    episode: PodcastEpisodeInfo, podcastTitle: String, fallbackImageURL: String?,
    podcastLanguage: String = ""
  ) {
    self.episode = episode
    self.podcastTitle = podcastTitle
    self.fallbackImageURL = fallbackImageURL
    self.podcastLanguage = podcastLanguage
    self.aiAnalysis = AIAnalysisCoordinator(
      episode: episode,
      podcastTitle: podcastTitle,
      podcastLanguage: podcastLanguage
    )

    // Now self is fully initialized — safe to hand back to the coordinator.
    self.aiAnalysis.attach(transcriptSource: self)

    parseDescription()

    // Check for active transcript job and start observing
    checkAndObserveTranscriptJob()
  }

  /// Episode key using centralized utility
  private var episodeKey: String {
    EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episode.title)
  }

  /// Checks if there's an active transcript job and starts observing
  private func checkAndObserveTranscriptJob() {
    if TranscriptManager.shared.activeJobs[episodeKey] != nil {
      syncTranscriptState()
      observeTranscriptManager()
    }
  }

  /// Immediately syncs transcriptState from current job status to avoid flash of 0%
  private func syncTranscriptState() {
    guard let job = TranscriptManager.shared.activeJobs[episodeKey] else { return }
    if let lang = job.detectedLanguage {
      transcriptDetectedLanguage = lang
    }
    switch job.status {
    case .queued:
      transcriptState = .transcribing(progress: 0)
    case .downloadingModel(let progress):
      transcriptState = .downloadingModel(progress: progress)
    case .transcribing(let progress):
      transcriptState = .transcribing(progress: progress)
    case .completed:
      loadExistingTranscriptTask?.cancel()
      loadExistingTranscriptTask = Task {
        await loadExistingTranscript()
      }
    case .failed(let error):
      transcriptState = .error(error)
    }
  }

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    // SwiftData is authoritative. If it has a language, use it and discard whatever
    // hint was passed at init. If it doesn't (podcast not yet cached, or no <language>
    // tag in the RSS), keep the hint — the picker's empty-language fallback handles it.
    if let lang = getPodcastLanguage() {
      podcastLanguage = lang
    }
    aiAnalysis.setPodcastLanguage(podcastLanguage)
    aiAnalysis.setModelContext(context)
    loadEpisodeModel()
    aiAnalysis.loadAIAnalysisFromSwiftData()
    aiAnalysis.observeCloudAnalysisJobFinished()
  }

  // MARK: - Episode Properties

  var title: String { episode.title }

  var pubDateString: String? {
    episode.pubDate?.formatted(date: .long, time: .omitted)
  }

  var imageURLString: String {
    episode.imageURL ?? fallbackImageURL ?? ""
  }

  var audioURL: String? { episode.audioURL }
  var isPlayDisabled: Bool {
    guard episode.audioURL != nil else { return true }
    // Can play if downloaded or has URL
    return !hasLocalAudio && episode.audioURL == nil
  }

  var playbackURL: String {
    // Prefer local file if available
    if let localPath = localAudioPath {
      // Use URL(fileURLWithPath:) to correctly percent-encode special chars
      // (spaces, #, Chinese characters, etc.) that "file://" + path breaks
      return URL(fileURLWithPath: localPath).absoluteString
    }
    return episode.audioURL ?? ""
  }

  var hasLocalAudio: Bool {
    if case .downloaded = downloadState {
      return true
    }
    return false
  }

  var localAudioPath: String? {
    if case .downloaded(let path) = downloadState {
      return path
    }
    return nil
  }

  // MARK: - Playback State

  /// Check if this episode is the current one loaded in audio manager (regardless of play state)
  var isCurrentEpisode: Bool {
    guard let currentEpisode = audioManager.currentEpisode else { return false }
    return currentEpisode.title == episode.title && currentEpisode.podcastTitle == podcastTitle
  }

  /// Check if this episode is currently playing
  var isPlayingThisEpisode: Bool {
    isCurrentEpisode && audioManager.isPlaying
  }

  var currentTime: TimeInterval {
    isPlayingThisEpisode ? audioManager.currentTime : (episodeModel?.lastPlaybackPosition ?? 0)
  }

  var duration: TimeInterval {
    isPlayingThisEpisode ? audioManager.duration : 0
  }

  var playbackRate: Float {
    audioManager.playbackRate
  }

  var currentCaption: String {
    isPlayingThisEpisode ? audioManager.currentCaption : ""
  }

  // Live mirrors of the SwiftData EpisodeDownloadModel. Reading any of these
  // in a SwiftUI view body registers an Observation dependency on
  // `episodeModel` and (transitively) on the @Model's accessed property, so
  // updates from PlaybackStateCoordinator propagate without a 5s notification
  // round-trip.
  var isStarred: Bool { episodeModel?.isStarred ?? false }
  var isCompleted: Bool { episodeModel?.isCompleted ?? false }
  var savedDuration: TimeInterval { episodeModel?.duration ?? 0 }
  var lastPlaybackPosition: TimeInterval { episodeModel?.lastPlaybackPosition ?? 0 }
  var playbackProgress: Double { episodeModel?.progress ?? 0 }
  var transcriptSource: String { episodeModel?.transcriptSource ?? "" }

  var formattedDuration: String? {
    episode.formattedDuration
  }

  var remainingTimeString: String? {
    episodeModel?.remainingTimeString
  }

  // MARK: - Actions

  func playAction() {
    guard let audioURLString = episode.audioURL else { return }

    // Prefer local file if available.
    // Use URL(fileURLWithPath:) to percent-encode special chars (#, spaces,
    // Chinese characters, etc.) — "file://" + path breaks URL(string:) in AVPlayer.
    let playbackURL: String
    if let localPath = localAudioPath {
      playbackURL = URL(fileURLWithPath: localPath).absoluteString
    } else {
      playbackURL = audioURLString
    }

    let playbackEpisode = PlaybackEpisode(
      id: episodeKey,
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: playbackURL,
      imageURL: imageURLString,
      episodeDescription: episode.podcastEpisodeDescription,
      pubDate: episode.pubDate,
      duration: episode.duration,
      guid: episode.guid
    )

    // Resume from saved position, but reset to 0 if episode was marked as completed
    // This allows users to replay completed episodes from the beginning
    var startTime: TimeInterval = 0
    if let model = episodeModel {
      if model.isCompleted {
        // Reset position for completed episodes (user wants to replay)
        model.lastPlaybackPosition = 0
        model.isCompleted = false
        try? modelContext?.save()
        startTime = 0

        // Force new player if this is the same episode (AVPlayer may be at end-of-media)
        if audioManager.currentEpisode?.id == episodeKey {
          audioManager.stop()
        }
      } else {
        startTime = model.lastPlaybackPosition
      }
    }

    // Use default speed from settings only for fresh plays (not resuming)
    let useDefaultSpeed = startTime == 0

    audioManager.play(
      episode: playbackEpisode,
      audioURL: playbackURL,
      startTime: startTime,
      imageURL: imageURLString,
      useDefaultSpeed: useDefaultSpeed
    )

    // Update last played date
    updateLastPlayed()
  }

  func seek(to time: TimeInterval) {
    audioManager.seek(to: time)
    savePlaybackPosition(time)
  }

  /// Seeks to a specific time, starting playback if needed. Used by AI timestamp badges.
  func seekToTime(_ seconds: TimeInterval) {
    if !isPlayingThisEpisode {
      playAction()
      seekTask?.cancel()
      seekTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(0.3))
        guard let self, !Task.isCancelled else { return }
        self.audioManager.seek(to: seconds)
      }
    } else {
      audioManager.seek(to: seconds)
    }
  }

  /// Shares an Apple Podcast link with a timestamp parameter (&t=seconds).
  func shareTimestampedLink(seconds: TimeInterval) {
    let totalSeconds = Int(seconds)
    shareTask?.cancel()
    shareTask = Task { [weak self] in
      guard let self else { return }
      do {
        let appleUrl = try await self.withTimeout(seconds: 5) {
          try await self.applePodcastService.getAppleEpisodeLink(
            episodeTitle: self.episode.title,
            episodeGuid: self.episode.guid
          )
        }
        guard !Task.isCancelled else { return }
        var urlString = appleUrl ?? self.episode.audioURL
        if totalSeconds > 0 {
          urlString = (urlString ?? "") + "&t=\(totalSeconds)"
        }
        self.shareWithURL(urlString)
      } catch {
        guard !Task.isCancelled else { return }
        var urlString = self.episode.audioURL ?? ""
        if totalSeconds > 0 {
          urlString += "&t=\(totalSeconds)"
        }
        self.shareWithURL(urlString)
      }
    }
  }

  func skipForward() {
    audioManager.skipForward()
  }

  func skipBackward() {
    audioManager.skipBackward()
  }

  func setPlaybackSpeed(_ rate: Float) {
    audioManager.setPlaybackRate(rate)
  }

  // MARK: - Download Management

  func startDownload() {
    downloadManager.downloadEpisode(
      episode: episode, podcastTitle: podcastTitle, language: podcastLanguage)
  }

  func cancelDownload() {
    downloadManager.cancelDownload(episodeTitle: episode.title, podcastTitle: podcastTitle)
  }

  func deleteDownload() {
    downloadManager.deleteDownload(episodeTitle: episode.title, podcastTitle: podcastTitle)
  }

  // MARK: - SwiftData Persistence

  private func loadEpisodeModel() {
    guard let context = modelContext else { return }

    let id = episodeKey
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == id }
    )

    do {
      let results = try context.fetch(descriptor)
      if let model = results.first {
        episodeModel = model
      } else {
        // Create new model
        createEpisodeModel(context: context)
      }
    } catch {
      logger.error("Failed to load episode model: \(error.localizedDescription)")
    }
  }

  private func createEpisodeModel(context: ModelContext) {
    guard let audioURL = episode.audioURL else { return }

    let model = EpisodeDownloadModel(
      episodeTitle: episode.title,
      podcastTitle: podcastTitle,
      audioURL: audioURL,
      imageURL: imageURLString,
      pubDate: episode.pubDate
    )
    context.insert(model)

    do {
      try context.save()
      episodeModel = model
    } catch {
      logger.error("Failed to create episode model: \(error.localizedDescription)")
    }
  }

  private func savePlaybackPosition(_ position: TimeInterval) {
    guard let model = episodeModel else { return }
    model.lastPlaybackPosition = position

    // Also save duration if we have it
    if audioManager.duration > 0 {
      model.duration = audioManager.duration
    }

    // Mark as completed if near the end (within 30 seconds)
    if model.duration > 0 && position >= model.duration - 30 {
      model.isCompleted = true
    }

    do {
      try modelContext?.save()
    } catch {
      logger.error("Failed to save playback position: \(error.localizedDescription)")
    }
  }

  private func updateLastPlayed() {
    guard let model = episodeModel else { return }
    model.lastPlayedDate = Date()
    model.playCount += 1

    // Save image URL and pub date if not already saved
    if model.imageURL == nil {
      model.imageURL = imageURLString
    }
    if model.pubDate == nil {
      model.pubDate = episode.pubDate
    }

    do {
      try modelContext?.save()
    } catch {
      logger.error("Failed to update last played: \(error.localizedDescription)")
    }
  }

  // MARK: - Description Parsing

  private func parseDescription() {
    let html = episode.podcastEpisodeDescription ?? ""

    guard !html.isEmpty else {
      descriptionContent = .empty
      return
    }

    let cacheKey = NSString(string: "\(html.hashValue)_16")
    if let cached = descriptionCache.object(forKey: cacheKey) {
      descriptionContent = .parsed(cached)
      return
    }

    #if os(iOS)
    let labelColor = UIColor.label
    #else
    let labelColor = NSColor.labelColor
    #endif

    let rootStyle = MarkupStyle(
      font: MarkupStyleFont(size: 16),
      foregroundColor: MarkupStyleColor(color: labelColor)
    )

    let parser = ZHTMLParserBuilder.initWithDefault()
      .set(rootStyle: rootStyle)
      .build()

    parseDescriptionTask = Task { [weak self] in
      guard let self else { return }
      let attributedString = parser.render(html)
      descriptionCache.setObject(attributedString, forKey: cacheKey)
      self.descriptionContent = .parsed(attributedString)
    }
  }

  // MARK: - Action Methods

  @ObservationIgnored
  private let applePodcastService = ApplePodcastService()

  @ObservationIgnored
  private var shareTask: Task<Void, Never>?

  func shareEpisode() {
    logger.debug("Share episode: \(self.episode.title)")

    // Cancel previous share task
    shareTask?.cancel()

    // Try to find Apple Podcast URL first with timeout
    shareTask = Task { [weak self] in
      guard let self else { return }
      do {
        let appleUrl = try await self.withTimeout(seconds: 5) {
          try await self.applePodcastService.getAppleEpisodeLink(
            episodeTitle: self.episode.title,
            episodeGuid: self.episode.guid
          )
        }
        if !Task.isCancelled {
          self.shareWithURL(appleUrl ?? self.episode.audioURL)
        }
      } catch {
        if !Task.isCancelled {
          // On error, fall back to audio URL
          self.shareWithURL(self.episode.audioURL)
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
    guard let urlString = urlString, let url = URL(string: urlString) else {
      logger.warning("No URL available for sharing")
      return
    }

    PlatformShareSheet.share(url: url)
  }

  func translateDescription() {
    logger.debug("Translate description requested")
    // Toggle to trigger the .translationTask modifiers for description, title, and podcast name
    descriptionTranslationTrigger.toggle()
    episodeTitleTranslationTrigger.toggle()
    podcastTitleTranslationTrigger.toggle()
  }

  // MARK: - Transcript Translation

  /// Translate to a specific language (called from language picker)
  func translateTo(_ language: TranslationTargetLanguage) {
    // Store the selected language for the translation triggers to use
    selectedTranslationLanguage = language
    let targetLang = language.languageIdentifier

    logger.debug("Translate requested to: \(language.displayName) (\(targetLang))")

    // Always trigger title/description translation (works without transcript)
    translationStatus = .preparingSession
    descriptionTranslationTrigger.toggle()
    episodeTitleTranslationTrigger.toggle()
    podcastTitleTranslationTrigger.toggle()

    // Skip transcript translation if no segments available
    guard !transcriptSegments.isEmpty else {
      logger.info("No transcript segments - translating title/description only")
      return
    }

    translationTask?.cancel()
    translationTask = Task { [weak self] in
      guard let self else { return }
      // Try to load existing transcript translation first
      if let translated = await self.translationService.loadExistingTranslation(
        segments: self.transcriptSegments,
        episodeTitle: self.episode.title,
        podcastTitle: self.podcastTitle,
        targetLanguage: targetLang
      ) {
        guard !Task.isCancelled else { return }
        self.transcriptSegments = translated
        self.regroupSentences()
        self.translationStatus = .completed
        // Auto-switch display mode so translated text is visible
        if self.subtitleSettings.displayMode == .originalOnly {
          self.subtitleSettings.displayMode = .dualTranslatedFirst
        }
        logger.info("Loaded cached translation for \(self.episode.title) in \(language.displayName)")
        return
      }

      guard !Task.isCancelled else { return }
      // No cached translation, trigger the transcript translation task
      self.transcriptTranslationTrigger.toggle()
    }
  }

  /// Check which translation languages are available (cached)
  func checkAvailableTranslations() {
    availableTranslationsTask?.cancel()
    availableTranslationsTask = Task { [weak self] in
      guard let self else { return }
      let available = await self.fileStorage.listAvailableTranslations(
        for: self.episode.title,
        podcastTitle: self.podcastTitle
      )
      guard !Task.isCancelled else { return }
      self.availableTranslationLanguages = available
      logger.info("Found \(available.count) cached translations: \(available)")
    }
  }

  /// Trigger transcript translation using Apple's Translation framework
  func translateTranscript() {
    guard !transcriptSegments.isEmpty else {
      logger.warning("No transcript segments to translate")
      return
    }

    // Use selected language or fall back to settings default
    let targetLang = (selectedTranslationLanguage ?? subtitleSettings.targetLanguage).languageIdentifier

    translationTask?.cancel()
    translationTask = Task { [weak self] in
      guard let self else { return }
      // Try to load existing translation first
      if let translated = await self.translationService.loadExistingTranslation(
        segments: self.transcriptSegments,
        episodeTitle: self.episode.title,
        podcastTitle: self.podcastTitle,
        targetLanguage: targetLang
      ) {
        guard !Task.isCancelled else { return }
        self.transcriptSegments = translated
        self.translationStatus = .completed
        logger.info("Loaded cached translation for \(self.episode.title)")
        return
      }

      guard !Task.isCancelled else { return }
      // No cached translation, trigger the translation task
      self.translationStatus = .preparingSession
      self.transcriptTranslationTrigger.toggle()
    }
  }

  /// Called by .translationTask when translation session is ready
  @available(iOS 17.4, macOS 14.4, *)
  func performTranscriptTranslation(using session: TranslationSession) async {
    #if canImport(Translation)
    let segments = self.transcriptSegments
    let total = segments.count

    guard total > 0 else {
      self.translationStatus = .failed("No segments to translate")
      return
    }

    self.translationStatus = .translating(progress: 0, completed: 0, total: total)

    // Extract Sendable Strings before the task group to avoid capture issues
    // with TranscriptSegment. Child tasks inherit @MainActor isolation so
    // accessing `session` across tasks is safe — no cross-actor boundary.
    let texts = segments.map(\.text)
    var translatedTexts = [Int: String](minimumCapacity: total)
    var completedCount = 0
    let concurrencyLimit = min(8, total)

    do {
      try await withThrowingTaskGroup(of: (Int, String).self) { group in
        var nextIndex = 0

        // Seed the initial batch
        while nextIndex < concurrencyLimit {
          let i = nextIndex
          group.addTask { (i, try await session.translate(texts[i]).targetText) }
          nextIndex += 1
        }

        // Collect results, updating progress and keeping the pipeline full
        for try await (i, translated) in group {
          try Task.checkCancellation()
          translatedTexts[i] = translated
          completedCount += 1
          let progress = Double(completedCount) / Double(total)
          self.translationStatus = .translating(progress: progress, completed: completedCount, total: total)

          if nextIndex < total {
            let i = nextIndex
            group.addTask { (i, try await session.translate(texts[i]).targetText) }
            nextIndex += 1
          }
        }
      }
    } catch is CancellationError {
      return
    } catch {
      logger.error("Translation failed: \(error.localizedDescription)")
      self.translationStatus = .failed(error.localizedDescription)
      return
    }

    var translatedSegments = segments
    for (i, text) in translatedTexts {
      translatedSegments[i].translatedText = text
    }

    // Save translated segments using selected language or settings default
    let targetLang = (self.selectedTranslationLanguage ?? self.subtitleSettings.targetLanguage).languageIdentifier

    do {
      try await translationService.saveTranslatedSRT(
        segments: translatedSegments,
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        targetLanguage: targetLang
      )
    } catch {
      logger.error("Failed to save translation: \(error.localizedDescription)")
    }

    self.transcriptSegments = translatedSegments
    self.regroupSentences()
    self.translationStatus = .completed
    // Update available translations
    self.availableTranslationLanguages.insert(targetLang)
    // Auto-switch display mode so translated text is visible
    if self.subtitleSettings.displayMode == .originalOnly {
      self.subtitleSettings.displayMode = .dualTranslatedFirst
    }

    logger.info("Completed translation for \(self.episode.title)")
    #endif
  }

  /// Called by .translationTask for description translation
  @available(iOS 17.4, macOS 14.4, *)
  func performDescriptionTranslation(using session: TranslationSession) async {
    #if canImport(Translation)
    guard let description = episode.podcastEpisodeDescription, !description.isEmpty else {
      return
    }

    // Strip HTML for translation
    let plainText = stripHTMLForTranslation(description)

    do {
      let response = try await session.translate(plainText)
      self.translatedDescription = response.targetText
      logger.info("Translated description for \(self.episode.title)")
    } catch {
      logger.error("Description translation failed: \(error.localizedDescription)")
    }
    #endif
  }

  /// Called by .translationTask for title translation
  @available(iOS 17.4, macOS 14.4, *)
  func performTitleTranslation(using session: TranslationSession) async {
    #if canImport(Translation)
    let title = episode.title
    guard !title.isEmpty else { return }

    do {
      let response = try await session.translate(title)
      self.translatedEpisodeTitle = response.targetText
      logger.info("Translated title for \(self.episode.title)")
    } catch {
      logger.error("Title translation failed: \(error.localizedDescription)")
    }
    #endif
  }

  /// Called by .translationTask for podcast name translation
  @available(iOS 17.4, macOS 14.4, *)
  func performPodcastTitleTranslation(using session: TranslationSession) async {
    #if canImport(Translation)
    let title = podcastTitle
    guard !title.isEmpty else { return }

    do {
      let response = try await session.translate(title)
      self.translatedPodcastTitle = response.targetText
      logger.info("Translated podcast title: \(title)")
    } catch {
      logger.error("Podcast title translation failed: \(error.localizedDescription)")
    }
    #endif
  }

  /// Strip HTML tags for translation
  private func stripHTMLForTranslation(_ html: String) -> String {
    var result = html
    // Remove HTML tags
    result = result.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    // Decode HTML entities
    result = decodeHTMLEntities(result)
    // Collapse whitespace
    result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Load existing translations for current segments
  func loadExistingTranslations() {
    guard !transcriptSegments.isEmpty else { return }
    let settings = SubtitleSettingsManager.shared
    let targetLang = settings.targetLanguage.languageIdentifier

    translationTask?.cancel()
    translationTask = Task { [weak self] in
      guard let self else { return }
      if let translated = await self.translationService.loadExistingTranslation(
        segments: self.transcriptSegments,
        episodeTitle: self.episode.title,
        podcastTitle: self.podcastTitle,
        targetLanguage: targetLang
      ) {
        guard !Task.isCancelled else { return }
        self.transcriptSegments = translated
        self.regroupSentences()
        // Auto-switch display mode so translated text is visible
        if self.subtitleSettings.displayMode == .originalOnly {
          self.subtitleSettings.displayMode = .dualTranslatedFirst
        }
        logger.info("Loaded existing translations for \(self.episode.title)")
      }
    }
  }

  /// Check if translation exists for current language
  var hasExistingTranslation: Bool {
    transcriptSegments.contains { $0.translatedText != nil }
  }

  /// The display mode to actually render — falls back to .originalOnly when no translation is available,
  /// so episodes without translation never show a confusing "dual subtitle" layout.
  var effectiveDisplayMode: SubtitleDisplayMode {
    let stored = subtitleSettings.displayMode
    guard stored.requiresTranslation else { return stored }
    return hasExistingTranslation ? stored : .originalOnly
  }

  func toggleStar() {
    // Create model if it doesn't exist
    if episodeModel == nil, let context = modelContext {
      createEpisodeModel(context: context)
    }

    guard let model = episodeModel else {
      logger.warning("Cannot toggle star: no episode model available")
      return
    }
    model.isStarred.toggle()

    do {
      try modelContext?.save()
    } catch {
      logger.error("Failed to save star state: \(error.localizedDescription)")
    }
  }

  func togglePlayed() {
    // Create model if it doesn't exist
    if episodeModel == nil, let context = modelContext {
      createEpisodeModel(context: context)
    }

    guard let model = episodeModel else {
      logger.warning("Cannot toggle played: no episode model available")
      return
    }
    model.isCompleted.toggle()
    if !model.isCompleted {
      model.lastPlaybackPosition = 0
    }

    do {
      try modelContext?.save()
    } catch {
      logger.error("Failed to save played state: \(error.localizedDescription)")
    }
  }

  func addToPlayNext() {
    guard let audioURLString = episode.audioURL else {
      logger.warning("Cannot add to play next: no audio URL")
      return
    }

    let playbackEpisode = PlaybackEpisode(
      id: episodeKey,
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: audioURLString,
      imageURL: imageURLString,
      episodeDescription: episode.podcastEpisodeDescription,
      pubDate: episode.pubDate,
      duration: episode.duration,
      guid: episode.guid
    )

    audioManager.playNext(playbackEpisode)
    logger.info("Added to play next: \(self.episode.title)")
  }

  // MARK: - RSS Transcript Methods

  /// Check if RSS transcript is available from the feed
  func checkRSSTranscriptAvailability() {
    rssTranscriptCheckTask?.cancel()
    rssTranscriptCheckTask = Task { [weak self] in
      guard let self else { return }
      let state = await self.transcriptDownloadService.getDownloadState(
        episodeTitle: self.episode.title,
        podcastTitle: self.podcastTitle,
        transcriptURL: self.episode.transcriptURL,
        transcriptType: self.episode.transcriptType
      )
      guard !Task.isCancelled else { return }
      self.rssTranscriptState = state

      // If already downloaded, load the transcript
      if case .downloaded = state {
        self.loadExistingTranscriptTask?.cancel()
        self.loadExistingTranscriptTask = Task { [weak self] in
          await self?.loadExistingTranscript()
        }
      }
    }
  }

  /// Download RSS transcript from the feed URL
  func downloadRSSTranscript() {
    guard case .available(let urlString, let type) = rssTranscriptState,
          let url = URL(string: urlString) else {
      logger.warning("Cannot download RSS transcript: not available")
      return
    }

    rssTranscriptDownloadTask?.cancel()
    rssTranscriptDownloadTask = Task { [weak self] in
      guard let self else { return }
      self.rssTranscriptState = .downloading(progress: 0.5)

      do {
        let savedURL = try await self.transcriptDownloadService.downloadTranscript(
          from: url,
          type: type,
          episodeTitle: self.episode.title,
          podcastTitle: self.podcastTitle
        )

        guard !Task.isCancelled else { return }
        self.rssTranscriptState = .downloaded(localPath: savedURL.path)
        logger.info("RSS transcript downloaded successfully")

        // Track that this transcript came from RSS
        if let model = self.episodeModel {
          model.transcriptSource = "rss"
          try? self.modelContext?.save()
        }

        // Load the transcript
        await self.loadExistingTranscript()

      } catch {
        guard !Task.isCancelled else { return }
        self.rssTranscriptState = .failed(error: error.localizedDescription)
        logger.error("RSS transcript download failed: \(error.localizedDescription)")
      }
    }
  }

  /// Check if RSS transcript is available and not yet downloaded
  var hasRSSTranscriptAvailable: Bool {
    if case .available = rssTranscriptState { return true }
    return false
  }

  /// Check if RSS transcript is being downloaded
  var isDownloadingRSSTranscript: Bool {
    if case .downloading = rssTranscriptState { return true }
    return false
  }

  /// Check if RSS transcript has been downloaded
  var hasDownloadedRSSTranscript: Bool {
    if case .downloaded = rssTranscriptState { return true }
    return false
  }

  // MARK: - Transcript Methods

  /// Looks up the podcast language from SwiftData.
  /// Returns nil when the podcast isn't in SwiftData or its language is empty,
  /// so callers can fall back to whatever hint they already have.
  private func getPodcastLanguage() -> String? {
    guard let context = modelContext else { return nil }

    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.title == podcastTitle }
    )

    do {
      let results = try context.fetch(descriptor)
      if let lang = results.first?.podcastInfo.language, !lang.isEmpty {
        return lang
      }
    } catch {
      logger.error("Failed to fetch podcast language: \(error.localizedDescription)")
    }

    return nil
  }

  func checkTranscriptStatus() {
    checkTranscriptTask?.cancel()
    checkTranscriptTask = Task { [weak self] in
      guard let self else { return }
      // Get podcast language and create transcript service
      let language = self.getPodcastLanguage() ?? self.podcastLanguage
      let transcriptService = TranscriptService(language: language)
      let modelReady = await transcriptService.isModelReady()

      // Check if transcript already exists (either from RSS or generated)
      let exists = await self.fileStorage.captionFileExists(
        for: self.episode.title,
        podcastTitle: self.podcastTitle
      )
      guard !Task.isCancelled else { return }
      self.isModelReady = modelReady

      if exists {
        await self.loadExistingTranscript()
      } else {
        guard !Task.isCancelled else { return }
        // Check for RSS transcript availability
        self.checkRSSTranscriptAvailability()
        // Check for active background transcript jobs and resume observation
        self.checkAndObserveTranscriptJob()
      }
    }
  }

  func generateTranscript() {
    let effectiveEngine = selectedTranscriptEngine ?? TranscriptEngine(
      rawValue: UserDefaults.standard.string(forKey: "transcriptEngine") ?? ""
    ) ?? .appleSpeech

    // Non-yap engines require a downloaded file
    if effectiveEngine != .yapServer, localAudioPath == nil {
      transcriptState = .error(
        "No local audio file available. Please download the episode first.")
      return
    }

    // Yap also needs either a local file or a remote URL
    if effectiveEngine == .yapServer, localAudioPath == nil, (episode.audioURL ?? "").isEmpty {
      transcriptState = .error("No audio URL available for this episode.")
      return
    }

    let language: String? = switch effectiveEngine {
    case .whisper:
      selectedTranscriptLanguage.flatMap { $0 == "auto" ? nil : $0 }
    case .appleSpeech:
      selectedTranscriptLanguage ?? (podcastLanguage.isEmpty ? nil : podcastLanguage)
    case .yapServer:
      selectedTranscriptLanguage ?? (podcastLanguage.isEmpty ? nil : podcastLanguage)
    }

    transcriptDetectedLanguage = nil

    logger.info("[generateTranscript] engine=\(effectiveEngine.rawValue) selectedLang=\(self.selectedTranscriptLanguage ?? "<nil>") resolvedLang=\(language ?? "<nil>") podcastLang=\(self.podcastLanguage)")

    TranscriptManager.shared.queueTranscript(
      episodeTitle: episode.title,
      podcastTitle: podcastTitle,
      audioPath: localAudioPath ?? "",
      audioRemoteURL: episode.audioURL,
      language: language,
      engine: selectedTranscriptEngine
    )

    // Start observing TranscriptManager state
    observeTranscriptManager()
  }

  /// Cancels an in-progress transcript generation job
  func cancelTranscript() {
    TranscriptManager.shared.cancelJob(
      episodeTitle: episode.title,
      podcastTitle: podcastTitle
    )
    isObservingTranscriptManager = false
    transcriptState = .idle
  }

  /// Regenerate transcript from downloaded audio, replacing any RSS transcript
  func regenerateTranscript() {
    // Clear current transcript and immediately show progress so the UI
    // doesn't flash the completed/idle state while the job is queuing.
    transcriptSegments = []
    groupedSentences = []
    transcriptText = ""
    transcriptState = .transcribing(progress: 0)

    // Mark as locally generated
    if let model = episodeModel {
      model.transcriptSource = "local"
      try? modelContext?.save()
    }

    // Trigger local transcription using existing infrastructure
    generateTranscript()
  }

  /// Observes TranscriptManager for job status updates
  private func observeTranscriptManager() {
    guard !isObservingTranscriptManager else { return }
    isObservingTranscriptManager = true
    startTranscriptObservation()
  }

  private func startTranscriptObservation() {
    // Don't start if we've stopped observing
    guard isObservingTranscriptManager else { return }

    withObservationTracking {
      // Access the property to register observation
      _ = TranscriptManager.shared.activeJobs
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self, self.isObservingTranscriptManager else { return }
        self.handleTranscriptJobUpdate()
        self.startTranscriptObservation()
      }
    }
  }

  private func handleTranscriptJobUpdate() {
    syncTranscriptState()
  }

  func copyTranscriptToClipboard() {
    PlatformClipboard.string = transcriptText
  }

  /// Cached word timings data from JSON file (for accurate word-level highlighting)
  private var wordTimingsData: TranscriptData?

  private func loadExistingTranscript() async {
    do {
      let content = try await fileStorage.loadCaptionFile(
        for: episode.title,
        podcastTitle: podcastTitle
      )

      // Also get the file date
      let fileDate = await fileStorage.getCaptionFileDate(
        for: episode.title,
        podcastTitle: podcastTitle
      )

      // Try to load word timings JSON (optional - may not exist for RSS transcripts)
      var timingsData: TranscriptData?
      if let wordTimingsJSON = try await fileStorage.loadWordTimingFile(
        for: episode.title,
        podcastTitle: podcastTitle
      ) {
        if let jsonData = wordTimingsJSON.data(using: .utf8) {
          timingsData = try? JSONDecoder().decode(TranscriptData.self, from: jsonData)
        }
      }

      transcriptText = content
      cachedTranscriptDate = fileDate
      wordTimingsData = timingsData
      transcriptState = .completed
      parseTranscriptSegments()
      await loadTranslationsAfterParsing()
    } catch {
      logger.error("Failed to load transcript: \(error.localizedDescription)")
      transcriptState = .error("Failed to load transcript: \(error.localizedDescription)")
    }
  }

  private func loadTranslationsAfterParsing() async {
    guard !transcriptSegments.isEmpty else { return }
    let settings = SubtitleSettingsManager.shared
    let targetLang = settings.targetLanguage.languageIdentifier

    if let translated = await translationService.loadExistingTranslation(
      segments: transcriptSegments,
      episodeTitle: episode.title,
      podcastTitle: podcastTitle,
      targetLanguage: targetLang
    ) {
      transcriptSegments = translated
      regroupSentences()
      translationStatus = .completed
      if subtitleSettings.displayMode == .originalOnly {
        subtitleSettings.displayMode = .dualTranslatedFirst
      }
      logger.info("Restored cached translation for \(self.episode.title)")
    } else if settings.autoTranslateOnLoad {
      translateTo(settings.targetLanguage)
    } else {
      translationStatus = .idle
    }
  }

  var hasTranscript: Bool {
    !transcriptText.isEmpty
  }

  /// Get the transcript generation date from the SRT file's modification date
  var transcriptGeneratedAt: Date? {
    get async {
      return await fileStorage.getCaptionFileDate(
        for: episode.title,
        podcastTitle: podcastTitle
      )
    }
  }

  /// Cached transcript generation date (for synchronous access in View)
  var cachedTranscriptDate: Date?

  /// Load transcript generation date
  func loadTranscriptDate() {
    loadTranscriptDateTask?.cancel()
    loadTranscriptDateTask = Task { [weak self] in
      guard let self else { return }
      let date = await self.transcriptGeneratedAt
      guard !Task.isCancelled else { return }
      self.cachedTranscriptDate = date
    }
  }

  /// Parses SRT content and returns clean text formatted in paragraphs
  /// Groups segments into sentences, then combines 4 sentences per paragraph
  var cleanTranscriptText: String {
    guard !transcriptSegments.isEmpty else { return "" }

    // Group segments into sentences using TranscriptGrouping
    let sentences = TranscriptGrouping.groupIntoSentences(transcriptSegments)

    // Combine 4 sentences per paragraph
    let sentencesPerParagraph = 4
    var paragraphs: [String] = []

    for startIndex in stride(from: 0, to: sentences.count, by: sentencesPerParagraph) {
      let endIndex = min(startIndex + sentencesPerParagraph, sentences.count)
      let chunk = sentences[startIndex..<endIndex]
      let paragraphText = CJKTextUtils.joinTexts(chunk.map { $0.text })
      paragraphs.append(paragraphText)
    }

    return paragraphs.joined(separator: "\n\n")
  }

  // MARK: - Live Captions Methods

  /// Finds word timings for a segment from the loaded word timings data
  /// - Parameters:
  ///   - segmentId: The segment ID (1-based)
  ///   - startTime: Segment start time
  ///   - endTime: Segment end time
  /// - Returns: Array of WordTiming if found, nil otherwise
  private func findWordTimingsForSegment(segmentId: Int, startTime: TimeInterval, endTime: TimeInterval) -> [WordTiming]? {
    guard let data = wordTimingsData else { return nil }

    // Try to find segment by ID first
    if let segment = data.segments.first(where: { $0.id == segmentId }) {
      return segment.wordTimings.map { timing in
        WordTiming(word: timing.word, startTime: timing.startTime, endTime: timing.endTime)
      }
    }

    // Fallback: find segment by time overlap
    for segment in data.segments {
      // Check if times roughly match (within 0.5s tolerance)
      if abs(segment.startTime - startTime) < 0.5 && abs(segment.endTime - endTime) < 0.5 {
        return segment.wordTimings.map { timing in
          WordTiming(word: timing.word, startTime: timing.startTime, endTime: timing.endTime)
        }
      }
    }

    return nil
  }

  /// Parses SRT content into transcript segments
  func parseTranscriptSegments() {
    guard !transcriptText.isEmpty else {
      transcriptSegments = []
      return
    }

    var segments: [TranscriptSegment] = []

    // Normalize line endings
    let normalizedText = transcriptText.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    // Use pre-compiled static regex for SRT parsing
    guard let regex = Self.srtRegex else {
      logger.error("SRT regex not available")
      return
    }

    let nsText = normalizedText as NSString
    let matches = regex.matches(
      in: normalizedText, options: [], range: NSRange(location: 0, length: nsText.length))

    logger.info(
      "Raw SRT text length: \(self.transcriptText.count), Found \(matches.count) potential entries via regex"
    )

    for (index, match) in matches.enumerated() {
      // Extract captured groups
      guard match.numberOfRanges >= 4 else { continue }

      let startTimeRange = match.range(at: 2)
      let endTimeRange = match.range(at: 3)

      guard startTimeRange.location != NSNotFound,
        endTimeRange.location != NSNotFound
      else { continue }

      let startTimeStr = nsText.substring(with: startTimeRange)
      let endTimeStr = nsText.substring(with: endTimeRange)

      guard let startTime = parseSRTTime(startTimeStr),
        let endTime = parseSRTTime(endTimeStr)
      else {
        logger.warning(
          "Entry \(index + 1): failed to parse times '\(startTimeStr)' -> '\(endTimeStr)'")
        continue
      }

      // Find text: starts after this match, ends at next match or end of string
      let textStart = match.range.location + match.range.length
      let textEnd: Int
      if index + 1 < matches.count {
        // Find the start of the next entry's index number
        let nextMatch = matches[index + 1]
        textEnd = nextMatch.range.location
      } else {
        textEnd = nsText.length
      }

      guard textStart < textEnd else { continue }

      let textRange = NSRange(location: textStart, length: textEnd - textStart)
      var text = nsText.substring(with: textRange)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\n", with: " ")

      // Remove any trailing index number that belongs to the next entry
      if let lastNewlineIndex = text.lastIndex(of: "\n") {
        let afterNewline = String(text[text.index(after: lastNewlineIndex)...])
        if afterNewline.trimmingCharacters(in: .whitespaces).allSatisfy({ $0.isNumber }) {
          text = String(text[..<lastNewlineIndex])
        }
      }

      text = text.trimmingCharacters(in: .whitespacesAndNewlines)

      // Decode HTML entities (e.g., &nbsp; -> space)
      text = decodeHTMLEntities(text)

      guard !text.isEmpty else {
        logger.warning("Entry \(index + 1): empty text")
        continue
      }

      // Look up word timings for this segment if available
      let wordTimings: [WordTiming]? = findWordTimingsForSegment(
        segmentId: index + 1,  // Word timings use 1-based IDs
        startTime: startTime,
        endTime: endTime
      )

      segments.append(
        TranscriptSegment(
          id: index,
          startTime: startTime,
          endTime: endTime,
          text: text,
          wordTimings: wordTimings
        ))
    }

    // Store raw SRT entries — sentence-block grouping is performed once below.
    transcriptSegments = segments
    logger.info(
      "Parsed \(segments.count) transcript segments from \(matches.count) regex matches"
    )

    // Precompute sentence grouping for transcript views
    regroupSentences()
  }

  /// Parses SRT time format (HH:MM:SS,mmm) to TimeInterval
  private func parseSRTTime(_ timeString: String) -> TimeInterval? {
    // Format: 00:00:10,500
    let components = timeString.replacingOccurrences(of: ",", with: ".").components(
      separatedBy: ":")
    guard components.count == 3 else { return nil }

    guard let hours = Double(components[0]),
      let minutes = Double(components[1]),
      let seconds = Double(components[2])
    else {
      return nil
    }

    return hours * 3600 + minutes * 60 + seconds
  }

  /// Decode common HTML entities in text
  private func decodeHTMLEntities(_ text: String) -> String {
    var result = text

    // Common HTML entities
    let entities: [(String, String)] = [
      ("&nbsp;", " "),
      ("&amp;", "&"),
      ("&lt;", "<"),
      ("&gt;", ">"),
      ("&quot;", "\""),
      ("&apos;", "'"),
      ("&#39;", "'"),
      ("&rsquo;", "'"),
      ("&lsquo;", "'"),
      ("&rdquo;", "\""),
      ("&ldquo;", "\""),
      ("&ndash;", "–"),
      ("&mdash;", "—"),
      ("&hellip;", "…"),
      ("&#160;", " "),  // Numeric form of &nbsp;
    ]

    for (entity, replacement) in entities {
      result = result.replacingOccurrences(of: entity, with: replacement)
    }

    // Handle numeric HTML entities (&#NNN;)
    if let regex = Self.numericEntityRegex {
      let nsString = result as NSString
      let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))

      // Process matches in reverse to avoid index shifting
      for match in matches.reversed() {
        if match.numberOfRanges >= 2 {
          let codeRange = match.range(at: 1)
          if let code = Int(nsString.substring(with: codeRange)),
             let scalar = Unicode.Scalar(code) {
            let replacement = String(Character(scalar))
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
          }
        }
      }
    }

    return result
  }

  /// Returns true if transcript is currently being processed (downloading model or transcribing)
  var isTranscriptProcessing: Bool {
    switch transcriptState {
    case .downloadingModel, .transcribing:
      return true
    default:
      return false
    }
  }

  /// Seeks to the start of a transcript segment and starts playback if needed.
  func seekToSegment(_ segment: TranscriptSegment) {
    let targetTime = segment.startTime
    logger.info("seekToSegment id=\(segment.id) target=\(String(format: "%.3f", targetTime))s")

    if !isPlayingThisEpisode {
      playAction()
      // Give the player time to initialize before seeking.
      seekTask?.cancel()
      seekTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(0.3))
        guard let self, !Task.isCancelled else { return }
        self.audioManager.seek(to: targetTime)
      }
    } else {
      audioManager.seek(to: targetTime)
    }
  }

  // MARK: - Sentence Grouping & Search Navigation

  /// Regroup segments into sentences. Call when transcriptSegments changes.
  func regroupSentences() {
    groupedSentences = TranscriptGrouping.groupIntoSentences(transcriptSegments)
    // Recompute search matches if there's an active query
    if !transcriptSearchQuery.isEmpty {
      updateSearchMatches(query: transcriptSearchQuery)
    }
  }

  /// Sentences to display. The transcript itself is never filtered by the
  /// search query — search lives in a dedicated sheet that surfaces matches
  /// as a result list. The active query still drives in-place highlighting
  /// inside the rendered rows.
  var transcriptSentences: [TranscriptSentence] {
    groupedSentences
  }

  /// Update search match IDs based on current query.
  ///
  /// Only includes sentences whose own text contains the query — the previous
  /// cross-boundary heuristic surfaced adjacent sentence pairs whose
  /// CJK-joined text matched, but that added rows to the result list that
  /// didn't visibly contain the keyword, which read like a bug.
  func updateSearchMatches(query: String) {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else {
      searchMatchIds = []
      currentMatchIndex = 0
      return
    }

    var ordered: [TranscriptSentence.ID] = []
    for sentence in groupedSentences where sentence.text.localizedStandardContains(trimmed) {
      ordered.append(sentence.id)
    }

    searchMatchIds = ordered
    currentMatchIndex = 0
  }

  /// Navigate to the next search match. Returns the sentence ID to scroll to.
  func nextMatch() -> TranscriptSentence.ID? {
    guard !searchMatchIds.isEmpty else { return nil }
    currentMatchIndex = (currentMatchIndex + 1) % searchMatchIds.count
    return searchMatchIds[currentMatchIndex]
  }

  /// Navigate to the previous search match. Returns the sentence ID to scroll to.
  func previousMatch() -> TranscriptSentence.ID? {
    guard !searchMatchIds.isEmpty else { return nil }
    currentMatchIndex = (currentMatchIndex - 1 + searchMatchIds.count) % searchMatchIds.count
    return searchMatchIds[currentMatchIndex]
  }

  // MARK: - AI (delegated to AIAnalysisCoordinator)
  // All AI lifecycle — on-device quick tags, cloud BYOK analysis, Q&A,
  // SwiftData persistence — lives on `aiAnalysis`. Views access it as
  // `viewModel.aiAnalysis.X`.


  // MARK: - Cleanup

  /// Cancel all active subscriptions to prevent memory leaks.
  /// AI-owned tasks are cancelled inside `aiAnalysis.cleanup()`.
  func cleanup() {
    isObservingTranscriptManager = false

    shareTask?.cancel(); shareTask = nil
    translationTask?.cancel(); translationTask = nil
    parseDescriptionTask?.cancel(); parseDescriptionTask = nil
    checkTranscriptTask?.cancel(); checkTranscriptTask = nil
    availableTranslationsTask?.cancel(); availableTranslationsTask = nil
    loadTranscriptDateTask?.cancel(); loadTranscriptDateTask = nil
    rssTranscriptCheckTask?.cancel(); rssTranscriptCheckTask = nil
    rssTranscriptDownloadTask?.cancel(); rssTranscriptDownloadTask = nil
    loadExistingTranscriptTask?.cancel(); loadExistingTranscriptTask = nil
    seekTask?.cancel(); seekTask = nil

    aiAnalysis.cleanup()

    // Release large transcript data
    transcriptText = ""
    transcriptSegments = []
    groupedSentences = []
    wordTimingsData = nil
  }

  // Tasks are cancelled via cleanup() from onDisappear; deinit removed
  // because accessing @MainActor properties from nonisolated deinit is invalid in Swift 6.
}

// MARK: - AIAnalysisTranscriptSource

/// The coordinator reads these three properties on demand via a weak ref
/// instead of caching them, so cloud-analysis kickoff always sees the
/// latest transcript without manual wiring.
extension EpisodeDetailViewModel: AIAnalysisTranscriptSource {}

