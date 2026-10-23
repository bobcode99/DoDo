//
//  TranslationCoordinator.swift
//  PodcastAnalyzer
//
//  Translation state for the detail screen: the transcript translation job
//  (owned app-wide by TranscriptTranslationManager, so it survives this
//  screen), plus description / episode-title / podcast-title translations via
//  Apple's Translation framework.
//
//  Extracted from EpisodeDetailViewModel. Reads transcript segments and
//  pushes results back through the TranscriptCoordinator's
//  `applyTranslations(_:)` API, so segment ownership stays with one type.
//

import Foundation
import Observation
import OSLog

#if canImport(Translation)
@preconcurrency import Translation
#endif

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranslationCoordinator")

@MainActor @Observable
final class TranslationCoordinator {

  // MARK: - Status

  /// The app-wide job is the single source of truth, so a re-entered page
  /// shows the progress of a translation started before it existed.
  var translationStatus: TranslationStatus { job?.status ?? .idle }

  /// Target of the transcript translation still preparing or running.
  var translatingLanguage: TranslationTargetLanguage? {
    guard let job, job.status.isTranslating else { return nil }
    return job.target
  }

  // MARK: - Translated copy

  var translatedDescription: String?
  var translatedEpisodeTitle: String?
  var translatedPodcastTitle: String?

  // MARK: - Language

  var selectedTranslationLanguage: TranslationTargetLanguage?
  var availableTranslationLanguages: Set<String> = []

  // MARK: - Trigger toggles (drive .translationTask in views)

  var transcriptTranslationTrigger: Bool = false
  var descriptionTranslationTrigger: Bool = false
  var episodeTitleTranslationTrigger: Bool = false
  var podcastTitleTranslationTrigger: Bool = false

  // MARK: - Inputs

  @ObservationIgnored let episode: PodcastEpisodeInfo
  @ObservationIgnored let podcastTitle: String
  @ObservationIgnored private let episodeKey: String
  @ObservationIgnored private var podcastLanguage: String

  /// Weak link to the transcript coordinator so we can read segments and
  /// push translated segments back via `applyTranslations(_:)`.
  @ObservationIgnored private weak var transcript: TranscriptCoordinator?

  @ObservationIgnored private let translationService = TranslationService.shared
  @ObservationIgnored private let subtitleSettings = SubtitleSettingsManager.shared
  @ObservationIgnored private let manager = TranscriptTranslationManager.shared

  // MARK: - Task Ownership

  @ObservationIgnored private var availableTranslationsTask: Task<Void, Never>?

  // MARK: - Init / Setup

  init(episode: PodcastEpisodeInfo, podcastTitle: String, podcastLanguage: String) {
    self.episode = episode
    self.podcastTitle = podcastTitle
    self.episodeKey = EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episode.title)
    self.podcastLanguage = podcastLanguage
  }

  func attach(transcript: TranscriptCoordinator) {
    self.transcript = transcript
  }

  func setPodcastLanguage(_ language: String) {
    self.podcastLanguage = language
  }

  // MARK: - Computed

  private var job: TranscriptTranslationManager.Job? { manager.jobs[episodeKey] }

  /// The transcript's own language, falling back to the feed's declared one.
  var sourceLanguage: Locale.Language? {
    TranscriptLanguageDetector.dominantLanguage(of: transcript?.transcriptSegments.map(\.text) ?? [])
      // Before the transcript loads, the episode's own text still beats the
      // feed tag: Taiwanese shows often declare a bare "zh", read as Simplified.
      ?? TranscriptLanguageDetector.dominantLanguage(
        of: [episode.title, stripHTMLForTranslation(episode.podcastEpisodeDescription ?? "")]
      )
      ?? translationService.detectSourceLanguage(from: podcastLanguage)
  }

  /// True when the live transcript carries translated text in any segment.
  var hasExistingTranslation: Bool {
    transcript?.transcriptSegments.contains { $0.translatedText != nil } ?? false
  }

  /// Falls back to `.originalOnly` when no translation is available, so the
  /// dual-subtitle layout never appears with no second-line text to show.
  var effectiveDisplayMode: SubtitleDisplayMode {
    let stored = subtitleSettings.displayMode
    guard stored.requiresTranslation else { return stored }
    return hasExistingTranslation ? stored : .originalOnly
  }

  // MARK: - Public API

  /// Top-level entry point: translate the description + both titles, and (if
  /// segments exist) the transcript. Called from the language picker.
  func translateTo(_ language: TranslationTargetLanguage) {
    // Covers auto-translate on load too: a show already in the target
    // language (often the device language) has nothing to translate.
    guard !language.isSameLanguage(as: sourceLanguage) else {
      logger.info("Skipping translation: content is already in \(language.displayName)")
      return
    }
    selectedTranslationLanguage = language
    logger.debug("Translate requested to: \(language.displayName) (\(language.languageIdentifier))")

    descriptionTranslationTrigger.toggle()
    episodeTitleTranslationTrigger.toggle()
    podcastTitleTranslationTrigger.toggle()

    guard let transcript, !transcript.transcriptSegments.isEmpty else {
      logger.info("No transcript segments - translating title/description only")
      return
    }

    if let cached = cachedTranslation(for: language) {
      // A job still running for another language would overwrite this when it finishes.
      manager.cancel(episodeKey: episodeKey)
      show(cached, in: language)
      return
    }
    guard sourceLanguage != nil else {
      manager.fail(
        episodeKey: episodeKey, target: language,
        message: String.appLocalized("Couldn't tell which language this transcript is in.")
      )
      return
    }
    manager.markPreparing(episodeKey: episodeKey, target: language)
    transcriptTranslationTrigger.toggle()
  }

  func translateDescription() {
    descriptionTranslationTrigger.toggle()
  }

  func checkAvailableTranslations() {
    availableTranslationsTask?.cancel()
    availableTranslationsTask = Task { [weak self] in
      guard let self else { return }
      let available = TranscriptStore.shared.availableTranslationLanguages(
        episodeTitle: self.episode.title,
        podcastTitle: self.podcastTitle
      )
      guard !Task.isCancelled else { return }
      self.availableTranslationLanguages = available
      logger.info("Found \(available.count) cached translations: \(available)")
    }
  }

  /// Called once the SRT parses: picks up this episode's translation job, else
  /// a cached translation, else auto-translates if the user opted in.
  func loadTranslationsAfterParsing() async {
    guard let transcript, !transcript.transcriptSegments.isEmpty else { return }

    if let job {
      if job.status == .completed {
        applyFinishedJob()
        return
      }
      if job.status.isTranslating {
        selectedTranslationLanguage = job.target
        return
      }
    }

    if let target = cachedTargetLanguage(), let cached = cachedTranslation(for: target) {
      show(cached, in: target)
      logger.info("Restored cached translation for \(self.episode.title)")
    } else if subtitleSettings.autoTranslateOnLoad {
      translateTo(subtitleSettings.targetLanguage)
    }
  }

  /// Drops the transcript translation in progress; no partial result is kept.
  func stopTranscriptTranslation() {
    manager.cancel(episodeKey: episodeKey)
  }

  func applyFinishedJob() {
    guard let job, job.status == .completed, let segments = job.segments,
          let transcript, !transcript.transcriptSegments.isEmpty else { return }
    show(segments, in: job.target)
  }

  // MARK: - .translationTask handlers

  /// The view-hosted session only prepares the language pair (which may ask
  /// the user to download it); the manager then translates without the view.
  @available(iOS 17.4, macOS 14.4, *)
  func prepareAndStart(using session: TranslationSession) async {
    // Read before suspending: leaving the page runs cleanup(), which empties
    // the live segments, but a prepared pair should still start the job.
    guard let target = selectedTranslationLanguage, let transcript, let source = sourceLanguage else { return }
    let segments = transcript.transcriptSegments
    do {
      try await session.prepareTranslation()
    } catch is CancellationError {
      // The page left mid-prompt; don't strand the job in .preparingSession.
      if let job, job.target == target, job.status == .preparingSession {
        manager.cancel(episodeKey: episodeKey)
      }
      return
    } catch {
      logger.error("Preparing translation failed: \(error.localizedDescription, privacy: .public)")
      manager.fail(episodeKey: episodeKey, target: target, message: error.localizedDescription)
      return
    }
    // Stopped (or replaced) while the pair was preparing.
    guard let job, job.target == target, job.status == .preparingSession else { return }

    manager.translate(
      segments,
      episodeKey: episodeKey,
      episodeTitle: episode.title,
      podcastTitle: podcastTitle,
      source: source,
      target: target
    )
  }

  @available(iOS 17.4, macOS 14.4, *)
  func performDescriptionTranslation(using session: TranslationSession) async {
    #if canImport(Translation)
    guard let description = episode.podcastEpisodeDescription, !description.isEmpty else { return }
    let plainText = stripHTMLForTranslation(description)
    do {
      let response = try await session.translate(plainText)
      translatedDescription = response.targetText
      logger.info("Translated description for \(self.episode.title)")
    } catch {
      logger.error("Description translation failed: \(error.localizedDescription, privacy: .public)")
    }
    #endif
  }

  @available(iOS 17.4, macOS 14.4, *)
  func performTitleTranslation(using session: TranslationSession) async {
    #if canImport(Translation)
    let title = episode.title
    guard !title.isEmpty else { return }
    do {
      let response = try await session.translate(title)
      translatedEpisodeTitle = response.targetText
      logger.info("Translated title for \(self.episode.title)")
    } catch {
      logger.error("Title translation failed: \(error.localizedDescription, privacy: .public)")
    }
    #endif
  }

  @available(iOS 17.4, macOS 14.4, *)
  func performPodcastTitleTranslation(using session: TranslationSession) async {
    #if canImport(Translation)
    let title = podcastTitle
    guard !title.isEmpty else { return }
    do {
      let response = try await session.translate(title)
      translatedPodcastTitle = response.targetText
      logger.info("Translated podcast title: \(title)")
    } catch {
      logger.error("Podcast title translation failed: \(error.localizedDescription, privacy: .public)")
    }
    #endif
  }

  // MARK: - Helpers

  private func cachedTranslation(for language: TranslationTargetLanguage) -> [TranscriptSegment]? {
    TranscriptStore.shared.loadTranslation(
      targetLanguage: language.languageIdentifier, episodeTitle: episode.title, podcastTitle: podcastTitle
    )
  }

  /// The default target when it's cached, else the first cached language, so a
  /// finished translation to a non-default language still shows on re-entry.
  private func cachedTargetLanguage() -> TranslationTargetLanguage? {
    let cached = TranscriptStore.shared.availableTranslationLanguages(
      episodeTitle: episode.title, podcastTitle: podcastTitle
    )
    let preferred = subtitleSettings.targetLanguage
    if cached.contains(preferred.languageIdentifier) { return preferred }
    return cached.sorted().lazy.compactMap(Self.targetLanguage(forIdentifier:)).first
  }

  /// Cached translations are keyed by `languageIdentifier`, which equals the
  /// raw value for every case except `.deviceLanguage`.
  private static func targetLanguage(forIdentifier identifier: String) -> TranslationTargetLanguage? {
    TranslationTargetLanguage(rawValue: identifier)
      ?? (TranslationTargetLanguage.deviceLanguage.languageIdentifier == identifier ? .deviceLanguage : nil)
  }

  private func show(_ translated: [TranscriptSegment], in language: TranslationTargetLanguage) {
    transcript?.applyTranslations(translated)
    selectedTranslationLanguage = language
    availableTranslationLanguages.insert(language.languageIdentifier)
    if subtitleSettings.displayMode == .originalOnly {
      subtitleSettings.displayMode = .dualTranslatedFirst
    }
  }

  /// Strip HTML tags + decode entities for translation payloads.
  /// Decode delegates to the TranscriptCoordinator's shared helper so the
  /// entity table is defined in exactly one place.
  private func stripHTMLForTranslation(_ html: String) -> String {
    var result = html
    result = result.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    if let transcript {
      result = transcript.decodeHTMLEntities(result)
    }
    result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Cleanup

  func cleanup() {
    availableTranslationsTask?.cancel(); availableTranslationsTask = nil
    // Preparing needs this page's session, which SwiftUI cancels as it
    // disappears; a running job belongs to the manager and keeps going.
    if job?.status == .preparingSession { manager.cancel(episodeKey: episodeKey) }
  }
}
