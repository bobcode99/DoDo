//
//  TranslationService.swift
//  PodcastAnalyzer
//
//  Actor-based translation service for managing translation state and storage.
//  NOTE: Actual translation using TranslationSession must happen in SwiftUI views
//  via .translationTask() modifier - TranslationSession cannot be directly initialized.
//

import Foundation
import OSLog

#if canImport(Translation)
import Translation
#endif

// MARK: - Translation Error

enum TranslationError: LocalizedError {
  case frameworkUnavailable
  case languageNotSupported(String)
  case sessionCreationFailed(Error)
  case translationFailed(Error)
  case noSegmentsToTranslate
  case cancelled
  case invalidConfiguration

  var errorDescription: String? {
    switch self {
    case .frameworkUnavailable:
      return "Translation requires iOS 17.4+ or macOS 14.4+"
    case .languageNotSupported(let lang):
      return "Language not supported: \(lang)"
    case .sessionCreationFailed(let error):
      return "Failed to create translation session: \(error.localizedDescription)"
    case .translationFailed(let error):
      return "Translation failed: \(error.localizedDescription)"
    case .noSegmentsToTranslate:
      return "No segments to translate"
    case .cancelled:
      return "Translation was cancelled"
    case .invalidConfiguration:
      return "Invalid translation configuration"
    }
  }
}

// MARK: - Translation Status

enum TranslationStatus: Equatable {
  case idle
  case preparingSession
  case translating(progress: Double, completed: Int, total: Int)
  case completed
  case failed(String)

  var isTranslating: Bool {
    switch self {
    case .preparingSession, .translating:
      return true
    default:
      return false
    }
  }

  static func == (lhs: TranslationStatus, rhs: TranslationStatus) -> Bool {
    switch (lhs, rhs) {
    case (.idle, .idle), (.completed, .completed), (.preparingSession, .preparingSession):
      return true
    case let (.translating(p1, c1, t1), .translating(p2, c2, t2)):
      return p1 == p2 && c1 == c2 && t1 == t2
    case let (.failed(e1), .failed(e2)):
      return e1 == e2
    default:
      return false
    }
  }
}

// MARK: - Translation Service

/// Service for managing translation state and storage.
/// NOTE: Actual translation must be triggered from SwiftUI views using .translationTask() modifier.
actor TranslationService {
  static let shared = TranslationService()

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranslationService")

  // Track active translations for cancellation
  private var activeTasks: [String: Task<Void, Never>] = [:]

  private init() {}

  // MARK: - Availability Check

  /// Check if Translation framework is available on this device
  nonisolated var isAvailable: Bool {
    #if canImport(Translation)
    if #available(iOS 17.4, macOS 14.4, *) {
      return true
    }
    #endif
    return false
  }

  // MARK: - Storage Methods

  /// Save translated segments, keyed by target language alongside the base transcript.
  func saveTranslatedSRT(
    segments: [TranscriptSegment],
    episodeTitle: String,
    podcastTitle: String,
    targetLanguage: String
  ) async throws {
    try await MainActor.run {
      try TranscriptStore.shared.saveTranslation(
        segments, targetLanguage: targetLanguage, episodeTitle: episodeTitle, podcastTitle: podcastTitle
      )
    }
    self.logger.info("Saved translation for \(episodeTitle) [\(targetLanguage)]")
  }

  /// Load existing translation, merged onto the stored base segments.
  func loadExistingTranslation(
    segments: [TranscriptSegment],
    episodeTitle: String,
    podcastTitle: String,
    targetLanguage: String
  ) async -> [TranscriptSegment]? {
    await MainActor.run {
      TranscriptStore.shared.loadTranslation(
        targetLanguage: targetLanguage, episodeTitle: episodeTitle, podcastTitle: podcastTitle
      )
    }
  }

  /// Check if a translation exists for this language
  func hasExistingTranslation(
    episodeTitle: String,
    podcastTitle: String,
    targetLanguage: String
  ) async -> Bool {
    await MainActor.run {
      TranscriptStore.shared.hasTranslation(
        targetLanguage: targetLanguage, episodeTitle: episodeTitle, podcastTitle: podcastTitle
      )
    }
  }

  // MARK: - Cancellation

  /// Cancel ongoing translation for an episode
  func cancelTranslation(episodeTitle: String, podcastTitle: String) {
    let taskKey = "\(podcastTitle)_\(episodeTitle)"
    if let task = activeTasks.removeValue(forKey: taskKey) {
      task.cancel()
      self.logger.info("Cancelled translation for: \(taskKey)")
    }
  }
}

// MARK: - Language Detection Helper

extension TranslationService {
  /// Detect source language from podcast language code
  @available(iOS 17.4, macOS 14.4, *)
  nonisolated func detectSourceLanguage(from podcastLanguage: String?) -> Locale.Language? {
    guard let lang = podcastLanguage, !lang.isEmpty else { return nil }

    // Map common podcast language codes to Locale.Language
    let normalized = lang.lowercased().replacingOccurrences(of: "_", with: "-")

    // Handle common language codes
    switch normalized {
    case "en", "en-us", "en-gb", "en-au":
      return Locale.Language(identifier: "en")
    case "zh", "zh-cn", "zh-hans":
      return Locale.Language(identifier: "zh-Hans")
    case "zh-tw", "zh-hant":
      return Locale.Language(identifier: "zh-Hant")
    case "ja", "ja-jp":
      return Locale.Language(identifier: "ja")
    case "ko", "ko-kr":
      return Locale.Language(identifier: "ko")
    case "es", "es-es", "es-mx":
      return Locale.Language(identifier: "es")
    case "fr", "fr-fr", "fr-ca":
      return Locale.Language(identifier: "fr")
    case "de", "de-de":
      return Locale.Language(identifier: "de")
    case "pt", "pt-br", "pt-pt":
      return Locale.Language(identifier: "pt")
    case "it", "it-it":
      return Locale.Language(identifier: "it")
    case "ru", "ru-ru":
      return Locale.Language(identifier: "ru")
    case "ar", "ar-sa":
      return Locale.Language(identifier: "ar")
    default:
      // Try to use the code directly
      return Locale.Language(identifier: normalized)
    }
  }
}

// MARK: - Translation Configuration Helper

#if canImport(Translation)
@available(iOS 17.4, macOS 14.4, *)
extension TranslationService {
  /// Create a translation configuration for use with SwiftUI's .translationTask()
  nonisolated func makeConfiguration(
    sourceLanguage: Locale.Language?,
    targetLanguage: Locale.Language
  ) -> TranslationSession.Configuration {
    if let source = sourceLanguage {
      return TranslationSession.Configuration(source: source, target: targetLanguage)
    } else {
      return TranslationSession.Configuration(target: targetLanguage)
    }
  }
}
#endif
