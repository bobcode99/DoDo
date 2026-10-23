//
//  TranscriptTranslationManager.swift
//  PodcastAnalyzer
//
//  App-wide owner of transcript translation jobs, keyed by episode key. A job
//  outlives the transcript page that started it, the same way
//  TranscriptManager owns transcription jobs: leaving the page neither
//  cancels the translation nor hides its progress when the page comes back.
//

import Foundation
import Observation
import OSLog

#if canImport(Translation)
@preconcurrency import Translation
#endif

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranscriptTranslationManager")

@MainActor @Observable
final class TranscriptTranslationManager {
  static let shared = TranscriptTranslationManager()

  struct Job: Equatable {
    let target: TranslationTargetLanguage
    var status: TranslationStatus
    /// Translated segments once `.completed`.
    var segments: [TranscriptSegment]?
  }

  /// Streams (segment index, translated text). Injected by tests; the
  /// Translation framework reports every language pair unsupported on the Simulator.
  typealias BatchTranslator = @Sendable (
    _ texts: [String], _ source: Locale.Language, _ target: Locale.Language
  ) -> AsyncThrowingStream<(Int, String), Error>

  /// Finished jobs stay until the next request for that episode, so a page
  /// opened after the job ended still picks up its result.
  private(set) var jobs: [String: Job] = [:]

  @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
  @ObservationIgnored private let translator: BatchTranslator

  init(translator: @escaping BatchTranslator = TranscriptTranslationManager.systemTranslator) {
    self.translator = translator
  }

  /// Shown while the page's view-hosted session prepares (and possibly
  /// downloads) the language pair, before `translate` takes over.
  func markPreparing(episodeKey: String, target: TranslationTargetLanguage) {
    if let job = jobs[episodeKey], job.target == target, job.status.isTranslating { return }
    cancel(episodeKey: episodeKey)
    jobs[episodeKey] = Job(target: target, status: .preparingSession)
  }

  func fail(episodeKey: String, target: TranslationTargetLanguage, message: String) {
    cancel(episodeKey: episodeKey)
    jobs[episodeKey] = Job(target: target, status: .failed(message))
  }

  func translate(
    _ segments: [TranscriptSegment],
    episodeKey: String,
    episodeTitle: String,
    podcastTitle: String,
    source: Locale.Language,
    target: TranslationTargetLanguage
  ) {
    if let job = jobs[episodeKey], job.target == target, case .translating = job.status { return }
    guard !segments.isEmpty else {
      fail(episodeKey: episodeKey, target: target, message: "No segments to translate")
      return
    }

    cancel(episodeKey: episodeKey)
    let total = segments.count
    jobs[episodeKey] = Job(target: target, status: .translating(progress: 0, completed: 0, total: total))
    let stream = translator(segments.map(\.text), source, Locale.Language(identifier: target.languageIdentifier))

    tasks[episodeKey] = Task {
      var translated = segments
      var completed = 0
      var reportedPercent = 0
      do {
        for try await (index, text) in stream {
          // A cancelled job's buffered results must not land on its replacement.
          try Task.checkCancellation()
          translated[index].translatedText = text
          completed += 1
          let percent = completed * 100 / total
          if percent != reportedPercent {
            reportedPercent = percent
            self.jobs[episodeKey]?.status = .translating(
              progress: Double(completed) / Double(total), completed: completed, total: total
            )
          }
        }
        // A cancelled stream ends without throwing.
        try Task.checkCancellation()
      } catch is CancellationError {
        return
      } catch {
        // A replaced job's stream can end with the framework's own error
        // rather than CancellationError; it must not fail its replacement.
        guard !Task.isCancelled else { return }
        logger.error("Translation failed: \(error.localizedDescription, privacy: .public)")
        self.tasks[episodeKey] = nil
        self.jobs[episodeKey]?.status = .failed(error.localizedDescription)
        return
      }

      do {
        try TranscriptStore.shared.saveTranslation(
          translated, targetLanguage: target.languageIdentifier,
          episodeTitle: episodeTitle, podcastTitle: podcastTitle
        )
      } catch {
        logger.error("Failed to save translation: \(error.localizedDescription, privacy: .public)")
      }
      self.tasks[episodeKey] = nil
      self.jobs[episodeKey] = Job(target: target, status: .completed, segments: translated)
      logger.info("Completed translation for \(episodeTitle) [\(target.languageIdentifier)]")
    }
  }

  func cancel(episodeKey: String) {
    tasks.removeValue(forKey: episodeKey)?.cancel()
    jobs[episodeKey] = nil
  }

  /// Translates with a session built from installed languages, so no view has
  /// to stay alive; the page's `.translationTask` only prepares the pair first.
  nonisolated static func systemTranslator(
    _ texts: [String], _ source: Locale.Language, _ target: Locale.Language
  ) -> AsyncThrowingStream<(Int, String), Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        let session = TranslationSession(installedSource: source, target: target)
        let requests = texts.enumerated().map { index, text in
          TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        do {
          for try await response in session.translate(batch: requests) {
            guard let index = response.clientIdentifier.flatMap(Int.init) else { continue }
            continuation.yield((index, response.targetText))
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
