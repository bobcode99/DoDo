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
struct WordTiming: Equatable, Sendable, Codable {
  let word: String
  let startTime: TimeInterval
  let endTime: TimeInterval
}

/// Represents a single transcript segment with timing information
struct TranscriptSegment: Identifiable, Equatable, Codable {
  let id: Int
  let startTime: TimeInterval
  let endTime: TimeInterval
  let text: String
  var translatedText: String?
  /// Word-level timing for accurate highlighting (from Speech framework)
  var wordTimings: [WordTiming]?
  /// Speaker cluster index for this line, fused from the diarization timeline
  /// at load time (max time overlap). Derived — never persisted into
  /// `segmentsJSON`; the source of truth is `EpisodeTranscriptModel.speakerTurnsJSON`.
  var speakerId: Int?

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

  // Playback state from SwiftData. NOT @ObservationIgnored — once set,
  // reading `episodeModel?.<property>` in computed properties registers
  // Observation through both this view model and the @Model itself, so any
  // write by PlaybackStateCoordinator (same main context) re-renders the
  // detail view without a notification round-trip.
  private(set) var episodeModel: EpisodeDownloadModel?

  @ObservationIgnored
  private(set) var modelContext: ModelContext?

  // Per-feature lifecycle is owned by focused coordinators. Views read state
  // via `viewModel.transcript.X`, `viewModel.translation.X`,
  // `viewModel.aiAnalysis.X` so @Observable invalidation stays scoped to the
  // sub-tree each piece of UI actually depends on.
  let transcript: TranscriptCoordinator
  let translation: TranslationCoordinator
  let aiAnalysis: AIAnalysisCoordinator

  // Tasks owned directly by the view model (description, share, generic seek
  // initiated from AI timestamp badges). Other task ownership lives on the
  // coordinators above.
  @ObservationIgnored
  private var parseDescriptionTask: Task<Void, Never>?

  @ObservationIgnored
  private var seekTask: Task<Void, Never>?

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
    self.transcript = TranscriptCoordinator(
      episode: episode,
      podcastTitle: podcastTitle,
      podcastLanguage: podcastLanguage
    )
    self.translation = TranslationCoordinator(
      episode: episode,
      podcastTitle: podcastTitle
    )
    self.aiAnalysis = AIAnalysisCoordinator(
      episode: episode,
      podcastTitle: podcastTitle,
      podcastLanguage: podcastLanguage
    )

    // Now self is fully initialized — wire the coordinators.
    self.transcript.attach(host: self)
    self.translation.attach(transcript: self.transcript)
    self.aiAnalysis.attach(transcriptSource: self)

    parseDescription()

    // Resume observation if a transcript job is still active for this episode
    self.transcript.checkAndObserveTranscriptJob()
  }

  /// Episode key using centralized utility
  private var episodeKey: String {
    EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episode.title)
  }

  /// Checks if there's an active transcript job and starts observing

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    // SwiftData is authoritative. If it has a language, use it and discard whatever
    // hint was passed at init. If it doesn't (podcast not yet cached, or no <language>
    // tag in the RSS), keep the hint — the picker's empty-language fallback handles it.
    if let lang = fetchPodcastLanguage(from: context) {
      podcastLanguage = lang
    }
    transcript.setPodcastLanguage(podcastLanguage)
    aiAnalysis.setPodcastLanguage(podcastLanguage)
    aiAnalysis.setModelContext(context)
    loadEpisodeModel()
    aiAnalysis.loadAIAnalysisFromSwiftData()
    aiAnalysis.observeCloudAnalysisJobFinished()
  }

  /// SwiftData podcast-language lookup. Inline — the coordinators each do
  /// their own fetch if they need it during async work.
  private func fetchPodcastLanguage(from context: ModelContext) -> String? {
    let title = podcastTitle
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.title == title }
    )
    if let lang = (try? context.fetch(descriptor))?.first?.podcastInfo.language,
       !lang.isEmpty { return lang }
    return nil
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

  // MARK: - Speaker Diarization (trigger only — no transcript UI yet)

  /// True while a diarization pass runs. Drives the toolbar button's disabled
  /// + "Identifying…" state.
  var isDiarizing = false

  /// One-shot result/error surfaced as an alert. Nil when nothing to show.
  var diarizationMessage: String?

  /// Runs on-device speaker diarization over the downloaded audio and persists
  /// the turns (+ default roster) via TranscriptStore. Requires local audio —
  /// the engine reads the file directly. No transcript rendering yet; this just
  /// proves the engine end-to-end and stores the timeline for later fusion.
  func diarize() {
    guard !isDiarizing, let path = localAudioPath else { return }
    isDiarizing = true
    diarizationMessage = nil
    Task { [weak self] in
      guard let self else { return }
      do {
        let output = try await DiarizationService().diarize(
          audioURL: URL(fileURLWithPath: path))
        try TranscriptStore.shared.saveDiarization(
          turns: output.turns, episodeTitle: episode.title, podcastTitle: podcastTitle)
        diarizationMessage =
          "Identified \(output.speakerCount) speaker(s) across \(output.turns.count) turns."
      } catch {
        diarizationMessage = "Diarization failed: \(error.localizedDescription)"
      }
      isDiarizing = false
    }
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
  var transcriptSource: String {
    TranscriptStore.shared.source(episodeTitle: episode.title, podcastTitle: podcastTitle)
  }

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
        model.setCompleted(false)
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
      logger.error("Failed to load episode model: \(error.localizedDescription, privacy: .public)")
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
      logger.error("Failed to create episode model: \(error.localizedDescription, privacy: .public)")
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
      model.setCompleted(true)
    }

    do {
      try modelContext?.save()
    } catch {
      logger.error("Failed to save playback position: \(error.localizedDescription, privacy: .public)")
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
      logger.error("Failed to update last played: \(error.localizedDescription, privacy: .public)")
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
      logger.error("Failed to save star state: \(error.localizedDescription, privacy: .public)")
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
    model.setCompleted(!model.isCompleted)
    model.lastPlaybackPosition = 0

    do {
      try modelContext?.save()
    } catch {
      logger.error("Failed to save played state: \(error.localizedDescription, privacy: .public)")
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

  // MARK: - AI (delegated to AIAnalysisCoordinator)
  // All AI lifecycle — on-device quick tags, cloud BYOK analysis, Q&A,
  // SwiftData persistence — lives on `aiAnalysis`. Views access it as
  // `viewModel.aiAnalysis.X`.


  // MARK: - Cleanup

  /// Cancel all active subscriptions to prevent memory leaks.
  /// Each coordinator cancels its own owned tasks.
  func cleanup() {
    shareTask?.cancel(); shareTask = nil
    parseDescriptionTask?.cancel(); parseDescriptionTask = nil
    seekTask?.cancel(); seekTask = nil

    transcript.cleanup()
    translation.cleanup()
    aiAnalysis.cleanup()
  }

  // Tasks are cancelled via cleanup() from onDisappear; deinit removed
  // because accessing @MainActor properties from nonisolated deinit is invalid in Swift 6.
}

// MARK: - Coordinator Bridges

/// Provides on-demand transcript access to AIAnalysisCoordinator. Reads
/// proxy through the TranscriptCoordinator, so the AI side always sees the
/// latest segments without manual wiring.
extension EpisodeDetailViewModel: AIAnalysisTranscriptSource {
  var transcriptText: String { transcript.transcriptText }
  var transcriptSegments: [TranscriptSegment] { transcript.transcriptSegments }
  var hasTranscript: Bool { transcript.hasTranscript }
}

/// Lets the TranscriptCoordinator reach back for playback (seek/play),
/// model context, the live download model, and translation reload.
extension EpisodeDetailViewModel: TranscriptHost {
  func loadTranslationsAfterParsing() async {
    await translation.loadTranslationsAfterParsing()
  }
}

