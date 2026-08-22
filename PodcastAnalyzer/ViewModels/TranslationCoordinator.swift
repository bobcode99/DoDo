//
//  TranslationCoordinator.swift
//  PodcastAnalyzer
//
//  Owns the translation lifecycle for the detail screen: per-segment
//  transcript translation, plus description / episode-title / podcast-title
//  translations via Apple's Translation framework.
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

  var translationStatus: TranslationStatus = .idle

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

  /// Weak link to the transcript coordinator so we can read segments and
  /// push translated segments back via `applyTranslations(_:)`.
  @ObservationIgnored private weak var transcript: TranscriptCoordinator?

  @ObservationIgnored private let translationService = TranslationService.shared
  @ObservationIgnored private let subtitleSettings = SubtitleSettingsManager.shared

  // MARK: - Task Ownership

  @ObservationIgnored private var translationTask: Task<Void, Never>?
  @ObservationIgnored private var availableTranslationsTask: Task<Void, Never>?

  // MARK: - Init / Setup

  init(episode: PodcastEpisodeInfo, podcastTitle: String) {
    self.episode = episode
    self.podcastTitle = podcastTitle
  }

  func attach(transcript: TranscriptCoordinator) {
    self.transcript = transcript
  }

  // MARK: - Computed

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
    selectedTranslationLanguage = language
    let targetLang = language.languageIdentifier

    logger.debug("Translate requested to: \(language.displayName) (\(targetLang))")

    descriptionTranslationTrigger.toggle()
    episodeTitleTranslationTrigger.toggle()
    podcastTitleTranslationTrigger.toggle()

    let segments = transcript?.transcriptSegments ?? []
    guard !segments.isEmpty else {
      // `translationStatus` tracks transcript translation only. Setting
      // .preparingSession before this guard stranded the progress circle at
      // 0 forever whenever the page had no transcript segments loaded.
      translationStatus = .idle
      logger.info("No transcript segments - translating title/description only")
      return
    }

    translationStatus = .preparingSession
    translationTask?.cancel()
    translationTask = Task { [weak self] in
      guard let self else { return }
      if let translated = await self.translationService.loadExistingTranslation(
        segments: segments,
        episodeTitle: self.episode.title,
        podcastTitle: self.podcastTitle,
        targetLanguage: targetLang
      ) {
        guard !Task.isCancelled else { return }
        self.transcript?.applyTranslations(translated)
        self.translationStatus = .completed
        if self.subtitleSettings.displayMode == .originalOnly {
          self.subtitleSettings.displayMode = .dualTranslatedFirst
        }
        logger.info("Loaded cached translation for \(self.episode.title) in \(language.displayName)")
        return
      }
      guard !Task.isCancelled else { return }
      self.transcriptTranslationTrigger.toggle()
    }
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

  func translateTranscript() {
    guard let transcript, !transcript.transcriptSegments.isEmpty else {
      logger.warning("No transcript segments to translate")
      return
    }

    let targetLang = (selectedTranslationLanguage ?? subtitleSettings.targetLanguage).languageIdentifier
    let segments = transcript.transcriptSegments

    translationTask?.cancel()
    translationTask = Task { [weak self] in
      guard let self else { return }
      if let translated = await self.translationService.loadExistingTranslation(
        segments: segments,
        episodeTitle: self.episode.title,
        podcastTitle: self.podcastTitle,
        targetLanguage: targetLang
      ) {
        guard !Task.isCancelled else { return }
        self.transcript?.applyTranslations(translated)
        self.translationStatus = .completed
        logger.info("Loaded cached translation for \(self.episode.title)")
        return
      }
      guard !Task.isCancelled else { return }
      self.translationStatus = .preparingSession
      self.transcriptTranslationTrigger.toggle()
    }
  }

  /// Called once the SRT parses — checks for a cached translation and
  /// auto-loads it (or kicks off auto-translate if the user opted in).
  func loadTranslationsAfterParsing() async {
    guard let transcript, !transcript.transcriptSegments.isEmpty else { return }
    let targetLang = subtitleSettings.targetLanguage.languageIdentifier

    if let translated = await translationService.loadExistingTranslation(
      segments: transcript.transcriptSegments,
      episodeTitle: episode.title,
      podcastTitle: podcastTitle,
      targetLanguage: targetLang
    ) {
      transcript.applyTranslations(translated)
      translationStatus = .completed
      if subtitleSettings.displayMode == .originalOnly {
        subtitleSettings.displayMode = .dualTranslatedFirst
      }
      logger.info("Restored cached translation for \(self.episode.title)")
    } else if subtitleSettings.autoTranslateOnLoad {
      translateTo(subtitleSettings.targetLanguage)
    } else {
      translationStatus = .idle
    }
  }

  /// Load existing translations for current segments
  func loadExistingTranslations() {
    guard let transcript, !transcript.transcriptSegments.isEmpty else { return }
    let targetLang = subtitleSettings.targetLanguage.languageIdentifier
    let segments = transcript.transcriptSegments

    translationTask?.cancel()
    translationTask = Task { [weak self] in
      guard let self else { return }
      if let translated = await self.translationService.loadExistingTranslation(
        segments: segments,
        episodeTitle: self.episode.title,
        podcastTitle: self.podcastTitle,
        targetLanguage: targetLang
      ) {
        guard !Task.isCancelled else { return }
        self.transcript?.applyTranslations(translated)
        self.translationStatus = .completed
        logger.info("Restored cached translation on demand")
      }
    }
  }

  // MARK: - .translationTask handlers

  @available(iOS 17.4, macOS 14.4, *)
  func performTranscriptTranslation(using session: TranslationSession) async {
    #if canImport(Translation)
    guard let transcript else {
      translationStatus = .failed("No transcript coordinator attached")
      return
    }
    let segments = transcript.transcriptSegments
    let total = segments.count
    guard total > 0 else {
      translationStatus = .failed("No segments to translate")
      return
    }

    translationStatus = .translating(progress: 0, completed: 0, total: total)

    let texts = segments.map(\.text)
    var translatedTexts = [Int: String](minimumCapacity: total)
    var completedCount = 0
    let concurrencyLimit = min(8, total)

    do {
      try await withThrowingTaskGroup(of: (Int, String).self) { group in
        var nextIndex = 0
        while nextIndex < concurrencyLimit {
          let i = nextIndex
          group.addTask { (i, try await session.translate(texts[i]).targetText) }
          nextIndex += 1
        }
        for try await (i, translated) in group {
          try Task.checkCancellation()
          translatedTexts[i] = translated
          completedCount += 1
          let progress = Double(completedCount) / Double(total)
          translationStatus = .translating(progress: progress, completed: completedCount, total: total)
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
      logger.error("Translation failed: \(error.localizedDescription, privacy: .public)")
      translationStatus = .failed(error.localizedDescription)
      return
    }

    var translatedSegments = segments
    for (i, text) in translatedTexts {
      translatedSegments[i].translatedText = text
    }

    let targetLang = (selectedTranslationLanguage ?? subtitleSettings.targetLanguage).languageIdentifier
    do {
      try await translationService.saveTranslatedSRT(
        segments: translatedSegments,
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        targetLanguage: targetLang
      )
    } catch {
      logger.error("Failed to save translation: \(error.localizedDescription, privacy: .public)")
    }

    self.transcript?.applyTranslations(translatedSegments)
    translationStatus = .completed
    availableTranslationLanguages.insert(targetLang)
    if subtitleSettings.displayMode == .originalOnly {
      subtitleSettings.displayMode = .dualTranslatedFirst
    }
    logger.info("Completed translation for \(self.episode.title)")
    #endif
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
    translationTask?.cancel(); translationTask = nil
    availableTranslationsTask?.cancel(); availableTranslationsTask = nil
  }
}
