//
//  TranscriptCoordinator.swift
//  PodcastAnalyzer
//
//  Owns the transcript lifecycle for a single episode: RSS-feed transcripts,
//  on-device generation via TranscriptManager, SRT parsing, word-timing
//  loading, sentence-block grouping, and in-transcript search navigation.
//
//  Extracted from EpisodeDetailViewModel so views observing transcript state
//  get scoped @Observable invalidation — a segment change no longer re-renders
//  view trees that only read episode metadata or AI state.
//

import Foundation
import Observation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranscriptCoordinator")

/// Playback bridge — the coordinator needs the audio manager for
/// `seekToSegment` and the local file path for generation checks.
@MainActor
protocol TranscriptPlaybackBridge: AnyObject {
  var audioManager: EnhancedAudioManager { get }
  var localAudioPath: String? { get }
  var isPlayingThisEpisode: Bool { get }
  func playAction()
}

/// Translation bridge — called once SRT parsing finishes so any cached
/// transcript translation can be restored before the user sees the page.
@MainActor
protocol TranscriptTranslationBridge: AnyObject {
  func loadTranslationsAfterParsing() async
}

/// SwiftData host — for the `EpisodeDownloadModel.transcriptSource` write
/// after RSS download / regeneration.
@MainActor
protocol TranscriptModelHost: AnyObject {
  var modelContext: ModelContext? { get }
  var episodeModel: EpisodeDownloadModel? { get }
}

/// Composite for compactness.
@MainActor
protocol TranscriptHost: TranscriptPlaybackBridge, TranscriptTranslationBridge, TranscriptModelHost {}

@MainActor @Observable
final class TranscriptCoordinator {

  // MARK: - Pre-compiled regex (single instance reused per parse)

  private static let srtRegex: NSRegularExpression? = {
    let entryPattern =
      #"(?:^|\n)(\d+)\n(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})\n"#
    return try? NSRegularExpression(pattern: entryPattern, options: [])
  }()

  private static let numericEntityRegex: NSRegularExpression? = {
    return try? NSRegularExpression(pattern: "&#(\\d+);", options: [])
  }()

  // MARK: - Generation / Engine State

  var transcriptState: TranscriptState = .idle
  var transcriptText: String = ""
  var isModelReady: Bool = false

  /// nil = engine default (RSS podcast language for Apple Speech, auto-detect for Whisper).
  var selectedTranscriptLanguage: String?
  /// nil = use global Settings default.
  var selectedTranscriptEngine: TranscriptEngine?
  /// Language detected by Whisper auto-detect during the last generation run.
  var transcriptDetectedLanguage: String?
  /// Chunk counts for the split Apple Speech path (nil when not chunked).
  /// Mirrored from the active TranscriptManager job so the generating UI can
  /// show a real "Part X/Y" instead of guessing.
  var transcriptPartProgress: TranscriptPartProgress?

  // MARK: - Segments & Grouping

  /// Raw SRT entries; sentence-block grouping is precomputed in `regroupSentences()`.
  var transcriptSegments: [TranscriptSegment] = []

  /// In-transcript search query — does not filter rendered rows; drives
  /// in-place highlighting and the navigation match list.
  var transcriptSearchQuery: String = ""

  /// Precomputed sentence grouping consumed via `transcriptSentences`.
  var groupedSentences: [TranscriptSentence] = []

  /// Search match navigation
  var searchMatchIds: [TranscriptSentence.ID] = []
  var currentMatchIndex: Int = 0

  // MARK: - RSS Transcript

  var rssTranscriptState: TranscriptDownloadState = .notAvailable

  // MARK: - Date Cache

  /// Synchronous mirror of the SRT file's modification date for view rendering.
  var cachedTranscriptDate: Date?

  /// Word-level timing data loaded from a sidecar JSON when present.
  @ObservationIgnored
  private var wordTimingsData: TranscriptData?

  // MARK: - Inputs / Host

  @ObservationIgnored let episode: PodcastEpisodeInfo
  @ObservationIgnored let podcastTitle: String
  @ObservationIgnored var podcastLanguage: String
  @ObservationIgnored private weak var host: TranscriptHost?

  @ObservationIgnored private let fileStorage = FileStorageManager.shared
  @ObservationIgnored private let transcriptDownloadService = TranscriptDownloadService.shared

  // MARK: - Task Ownership

  @ObservationIgnored private var checkTranscriptTask: Task<Void, Never>?
  @ObservationIgnored private var rssTranscriptCheckTask: Task<Void, Never>?
  @ObservationIgnored private var rssTranscriptDownloadTask: Task<Void, Never>?
  @ObservationIgnored private var loadExistingTranscriptTask: Task<Void, Never>?
  @ObservationIgnored private var loadTranscriptDateTask: Task<Void, Never>?
  @ObservationIgnored private var seekTask: Task<Void, Never>?

  @ObservationIgnored private var isObservingTranscriptManager = false

  // MARK: - Init / Setup

  init(
    episode: PodcastEpisodeInfo,
    podcastTitle: String,
    podcastLanguage: String
  ) {
    self.episode = episode
    self.podcastTitle = podcastTitle
    self.podcastLanguage = podcastLanguage
  }

  /// Attach the owner after it's fully initialized. `weak` keeps the
  /// coordinator-↔-owner cycle GC-free.
  func attach(host: TranscriptHost) {
    self.host = host
  }

  func setPodcastLanguage(_ language: String) {
    self.podcastLanguage = language
  }

  // MARK: - Computed

  var hasTranscript: Bool { !transcriptText.isEmpty }

  /// SRT modification date — slow async path. UI should read `cachedTranscriptDate`.
  var transcriptGeneratedAt: Date? {
    get async {
      await fileStorage.getCaptionFileDate(
        for: episode.title,
        podcastTitle: podcastTitle
      )
    }
  }

  /// Plain-text paragraphs assembled from segments — used for clipboard, share, AI.
  var cleanTranscriptText: String {
    guard !transcriptSegments.isEmpty else { return "" }
    let sentences = TranscriptGrouping.groupIntoSentences(transcriptSegments)
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

  var isTranscriptProcessing: Bool {
    switch transcriptState {
    case .downloadingModel, .transcribing: return true
    default: return false
    }
  }

  var hasRSSTranscriptAvailable: Bool {
    if case .available = rssTranscriptState { return true }
    return false
  }

  var isDownloadingRSSTranscript: Bool {
    if case .downloading = rssTranscriptState { return true }
    return false
  }

  var hasDownloadedRSSTranscript: Bool {
    if case .downloaded = rssTranscriptState { return true }
    return false
  }

  var transcriptSentences: [TranscriptSentence] { groupedSentences }

  // MARK: - Episode key

  private var episodeKey: String {
    EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episode.title)
  }

  // MARK: - TranscriptManager Observation

  /// Checks if there's an active transcript job and starts observing.
  func checkAndObserveTranscriptJob() {
    if TranscriptManager.shared.activeJobs[episodeKey] != nil {
      syncTranscriptState()
      observeTranscriptManager()
    }
  }

  /// Immediately syncs transcriptState from current job status to avoid 0% flash.
  private func syncTranscriptState() {
    guard let job = TranscriptManager.shared.activeJobs[episodeKey] else { return }
    if let lang = job.detectedLanguage {
      transcriptDetectedLanguage = lang
    }
    transcriptPartProgress = job.partProgress
    switch job.status {
    case .queued:
      transcriptState = .transcribing(progress: 0)
    case .downloadingModel(let progress):
      transcriptState = .downloadingModel(progress: progress)
    case .transcribing(let progress):
      transcriptState = .transcribing(progress: progress)
    case .completed:
      loadExistingTranscriptTask?.cancel()
      loadExistingTranscriptTask = Task { [weak self] in
        await self?.loadExistingTranscript()
      }
    case .failed(let error):
      transcriptState = .error(error)
    }
  }

  private func observeTranscriptManager() {
    guard !isObservingTranscriptManager else { return }
    isObservingTranscriptManager = true
    startTranscriptObservation()
  }

  private func startTranscriptObservation() {
    guard isObservingTranscriptManager else { return }
    withObservationTracking {
      _ = TranscriptManager.shared.activeJobs
    } onChange: {
      Task { @MainActor [weak self] in
        guard let self, self.isObservingTranscriptManager else { return }
        self.syncTranscriptState()
        self.startTranscriptObservation()
      }
    }
  }

  // MARK: - RSS Transcript

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
      if case .downloaded = state {
        self.loadExistingTranscriptTask?.cancel()
        self.loadExistingTranscriptTask = Task { [weak self] in
          await self?.loadExistingTranscript()
        }
      }
    }
  }

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
        if let host = self.host, let model = host.episodeModel {
          model.transcriptSource = "rss"
          try? host.modelContext?.save()
        }

        await self.loadExistingTranscript()
      } catch {
        guard !Task.isCancelled else { return }
        self.rssTranscriptState = .failed(error: error.localizedDescription)
        logger.error("RSS transcript download failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  // MARK: - Status / Generation

  /// SwiftData podcast-language lookup; nil falls back to the in-memory hint.
  private func podcastLanguageFromSwiftData() -> String? {
    guard let context = host?.modelContext else { return nil }
    let title = podcastTitle
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.title == title }
    )
    do {
      let results = try context.fetch(descriptor)
      if let lang = results.first?.podcastInfo.language, !lang.isEmpty { return lang }
    } catch {
      logger.error("Failed to fetch podcast language: \(error.localizedDescription, privacy: .public)")
    }
    return nil
  }

  func checkTranscriptStatus() {
    checkTranscriptTask?.cancel()
    checkTranscriptTask = Task { [weak self] in
      guard let self else { return }
      let language = self.podcastLanguageFromSwiftData() ?? self.podcastLanguage
      let transcriptService = TranscriptService(language: language)
      let modelReady = await transcriptService.isModelReady()

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
        self.checkRSSTranscriptAvailability()
        self.checkAndObserveTranscriptJob()
      }
    }
  }

  func generateTranscript() {
    let effectiveEngine = selectedTranscriptEngine ?? TranscriptEngine(
      rawValue: UserDefaults.standard.string(forKey: "transcriptEngine") ?? ""
    ) ?? .appleSpeech

    let localAudioPath = host?.localAudioPath

    if effectiveEngine != .yapServer, localAudioPath == nil {
      transcriptState = .error(
        "No local audio file available. Please download the episode first.")
      return
    }

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
    observeTranscriptManager()
  }

  func cancelTranscript() {
    TranscriptManager.shared.cancelJob(
      episodeTitle: episode.title,
      podcastTitle: podcastTitle
    )
    isObservingTranscriptManager = false
    transcriptState = .idle
  }

  /// Regenerate transcript from downloaded audio, replacing any RSS transcript.
  func regenerateTranscript() {
    transcriptSegments = []
    groupedSentences = []
    transcriptText = ""
    transcriptState = .transcribing(progress: 0)

    if let host, let model = host.episodeModel {
      model.transcriptSource = "local"
      try? host.modelContext?.save()
    }

    generateTranscript()
  }

  // MARK: - Loading / Parsing

  func copyTranscriptToClipboard() {
    PlatformClipboard.string = transcriptText
  }

  private func loadExistingTranscript() async {
    do {
      let content = try await fileStorage.loadCaptionFile(
        for: episode.title,
        podcastTitle: podcastTitle
      )
      let fileDate = await fileStorage.getCaptionFileDate(
        for: episode.title,
        podcastTitle: podcastTitle
      )

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
      await host?.loadTranslationsAfterParsing()
    } catch {
      logger.error("Failed to load transcript: \(error.localizedDescription, privacy: .public)")
      transcriptState = .error("Failed to load transcript: \(error.localizedDescription)")
    }
  }

  func loadTranscriptDate() {
    loadTranscriptDateTask?.cancel()
    loadTranscriptDateTask = Task { [weak self] in
      guard let self else { return }
      let date = await self.transcriptGeneratedAt
      guard !Task.isCancelled else { return }
      self.cachedTranscriptDate = date
    }
  }

  /// Find word timings for a segment from the loaded JSON sidecar.
  private func findWordTimingsForSegment(
    segmentId: Int,
    startTime: TimeInterval,
    endTime: TimeInterval
  ) -> [WordTiming]? {
    guard let data = wordTimingsData else { return nil }
    if let segment = data.segments.first(where: { $0.id == segmentId }) {
      return segment.wordTimings.map { timing in
        WordTiming(word: timing.word, startTime: timing.startTime, endTime: timing.endTime)
      }
    }
    for segment in data.segments {
      if abs(segment.startTime - startTime) < 0.5 && abs(segment.endTime - endTime) < 0.5 {
        return segment.wordTimings.map { timing in
          WordTiming(word: timing.word, startTime: timing.startTime, endTime: timing.endTime)
        }
      }
    }
    return nil
  }

  func parseTranscriptSegments() {
    guard !transcriptText.isEmpty else {
      transcriptSegments = []
      return
    }

    var segments: [TranscriptSegment] = []
    let normalizedText = transcriptText.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    guard let regex = Self.srtRegex else {
      logger.error("SRT regex not available")
      return
    }

    let nsText = normalizedText as NSString
    let matches = regex.matches(
      in: normalizedText, options: [], range: NSRange(location: 0, length: nsText.length))

    logger.info("Raw SRT text length: \(self.transcriptText.count), Found \(matches.count) potential entries via regex")

    for (index, match) in matches.enumerated() {
      guard match.numberOfRanges >= 4 else { continue }

      let startTimeRange = match.range(at: 2)
      let endTimeRange = match.range(at: 3)
      guard startTimeRange.location != NSNotFound,
            endTimeRange.location != NSNotFound else { continue }

      let startTimeStr = nsText.substring(with: startTimeRange)
      let endTimeStr = nsText.substring(with: endTimeRange)

      guard let startTime = parseSRTTime(startTimeStr),
            let endTime = parseSRTTime(endTimeStr) else {
        logger.warning("Entry \(index + 1): failed to parse times '\(startTimeStr)' -> '\(endTimeStr)'")
        continue
      }

      let textStart = match.range.location + match.range.length
      let textEnd: Int
      if index + 1 < matches.count {
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

      if let lastNewlineIndex = text.lastIndex(of: "\n") {
        let afterNewline = String(text[text.index(after: lastNewlineIndex)...])
        if afterNewline.trimmingCharacters(in: .whitespaces).allSatisfy({ $0.isNumber }) {
          text = String(text[..<lastNewlineIndex])
        }
      }
      text = text.trimmingCharacters(in: .whitespacesAndNewlines)
      text = decodeHTMLEntities(text)
      guard !text.isEmpty else {
        logger.warning("Entry \(index + 1): empty text")
        continue
      }

      let wordTimings: [WordTiming]? = findWordTimingsForSegment(
        segmentId: index + 1,
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

    transcriptSegments = segments
    logger.info("Parsed \(segments.count) transcript segments from \(matches.count) regex matches")
    regroupSentences()
  }

  private func parseSRTTime(_ timeString: String) -> TimeInterval? {
    let components = timeString.replacingOccurrences(of: ",", with: ".").components(
      separatedBy: ":")
    guard components.count == 3 else { return nil }
    guard let hours = Double(components[0]),
          let minutes = Double(components[1]),
          let seconds = Double(components[2]) else { return nil }
    return hours * 3600 + minutes * 60 + seconds
  }

  /// Decode common HTML entities — used by SRT parsing and by translation
  /// (TranslationCoordinator calls this via the public surface).
  func decodeHTMLEntities(_ text: String) -> String {
    var result = text
    let entities: [(String, String)] = [
      ("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
      ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
      ("&rsquo;", "'"), ("&lsquo;", "'"), ("&rdquo;", "\""), ("&ldquo;", "\""),
      ("&ndash;", "\u{2013}"), ("&mdash;", "\u{2014}"), ("&hellip;", "\u{2026}"),
      ("&#160;", " "),
    ]
    for (entity, replacement) in entities {
      result = result.replacingOccurrences(of: entity, with: replacement)
    }
    if let regex = Self.numericEntityRegex {
      let nsString = result as NSString
      let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
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

  // MARK: - Seek

  func seekToSegment(_ segment: TranscriptSegment) {
    guard let host else { return }
    let targetTime = segment.startTime
    logger.info("seekToSegment id=\(segment.id) target=\(String(format: "%.3f", targetTime))s")
    if !host.isPlayingThisEpisode {
      host.playAction()
      seekTask?.cancel()
      seekTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(0.3))
        guard let self, !Task.isCancelled, let host = self.host else { return }
        host.audioManager.seek(to: targetTime)
      }
    } else {
      host.audioManager.seek(to: targetTime)
    }
  }

  // MARK: - Sentence Grouping & Search

  func regroupSentences() {
    groupedSentences = TranscriptGrouping.groupIntoSentences(transcriptSegments)
    if !transcriptSearchQuery.isEmpty {
      updateSearchMatches(query: transcriptSearchQuery)
    }
  }

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

  func nextMatch() -> TranscriptSentence.ID? {
    guard !searchMatchIds.isEmpty else { return nil }
    currentMatchIndex = (currentMatchIndex + 1) % searchMatchIds.count
    return searchMatchIds[currentMatchIndex]
  }

  func previousMatch() -> TranscriptSentence.ID? {
    guard !searchMatchIds.isEmpty else { return nil }
    currentMatchIndex = (currentMatchIndex - 1 + searchMatchIds.count) % searchMatchIds.count
    return searchMatchIds[currentMatchIndex]
  }

  // MARK: - Translation handshake

  /// Public API the TranslationCoordinator uses to push translated segments
  /// back into the live transcript view.
  func applyTranslations(_ translated: [TranscriptSegment]) {
    transcriptSegments = translated
    regroupSentences()
  }

  // MARK: - Cleanup

  func cleanup() {
    isObservingTranscriptManager = false

    checkTranscriptTask?.cancel(); checkTranscriptTask = nil
    rssTranscriptCheckTask?.cancel(); rssTranscriptCheckTask = nil
    rssTranscriptDownloadTask?.cancel(); rssTranscriptDownloadTask = nil
    loadExistingTranscriptTask?.cancel(); loadExistingTranscriptTask = nil
    loadTranscriptDateTask?.cancel(); loadTranscriptDateTask = nil
    seekTask?.cancel(); seekTask = nil

    transcriptText = ""
    transcriptSegments = []
    groupedSentences = []
    wordTimingsData = nil
  }
}

// MARK: - Engine / language config helpers
//
// Shared by the transcript config + generating views so the derived engine and
// language naming lives in one place instead of being duplicated per view.
extension TranscriptCoordinator {
  /// Engine in effect: explicit selection, else global default, else Apple Speech.
  var effectiveEngine: TranscriptEngine {
    selectedTranscriptEngine ?? TranscriptEngine(
      rawValue: UserDefaults.standard.string(forKey: "transcriptEngine") ?? ""
    ) ?? .appleSpeech
  }

  /// Maps a raw language code onto the closest locale the current engine supports.
  func resolvedLanguage(_ code: String) -> String {
    guard !code.isEmpty else { return code }
    let locales = SettingsViewModel.locales(for: effectiveEngine)
    let lower = code.lowercased()
    if locales.contains(where: { $0.id == lower }) { return lower }
    if let match = locales.first(where: { $0.id.hasPrefix(lower + "-") }) { return match.id }
    let base = lower.split(separator: "-").first.map(String.init) ?? lower
    if let match = locales.first(where: { $0.id == base || $0.id.hasPrefix(base + "-") }) { return match.id }
    return lower
  }

  /// Languages offered in the picker, injecting the podcast's own language when
  /// the engine's standard list doesn't already cover it.
  var pickerLocales: [SettingsViewModel.TranscriptLocaleOption] {
    let standard = SettingsViewModel.locales(for: effectiveEngine)
    guard !podcastLanguage.isEmpty else { return standard }
    let lang = podcastLanguage.lowercased()
    let resolved = resolvedLanguage(lang)
    if standard.contains(where: { $0.id == resolved }) { return standard }
    let displayName = Locale.current.localizedString(forLanguageCode: lang) ?? lang
    return [SettingsViewModel.TranscriptLocaleOption(id: lang, name: "\(displayName) (podcast)")] + standard
  }

  /// Human-readable name of the language this job will (or did) transcribe in.
  var transcriptLanguageName: String {
    if effectiveEngine == .whisper, selectedTranscriptLanguage == nil {
      if let detected = transcriptDetectedLanguage {
        return pickerLocales.first { $0.id == detected }?.name
          ?? Locale.current.localizedString(forLanguageCode: detected)
          ?? detected
      }
      return "Auto-detect"
    }
    let code = selectedTranscriptLanguage ?? podcastLanguage
    return pickerLocales.first { $0.id == resolvedLanguage(code) }?.name ?? code
  }
}
