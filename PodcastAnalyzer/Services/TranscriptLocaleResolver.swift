//
//  TranscriptLocaleResolver.swift
//  PodcastAnalyzer
//
//  Locale resolution for podcast language codes.
//

import Foundation

/// Converts podcast RSS language codes to Foundation Locale identifiers.
@available(iOS 26.0, *)
public enum TranscriptLocaleResolver {

  /// Default region mappings for language-only codes.
  /// Speech framework requires full locale identifiers (e.g., "en_US" not just "en").
  private nonisolated static let defaultRegions: [String: String] = [
    "en": "US", "zh": "TW", "ja": "JP", "ko": "KR",
    "fr": "FR", "de": "DE", "es": "ES", "it": "IT",
    "pt": "BR", "ru": "RU", "ar": "SA", "hi": "IN",
    "th": "TH", "vi": "VN", "id": "ID", "ms": "MY",
    "nl": "NL", "pl": "PL", "tr": "TR", "uk": "UA",
    "cs": "CZ", "el": "GR", "he": "IL", "ro": "RO",
    "hu": "HU", "sv": "SE", "da": "DK", "fi": "FI",
    "nb": "NO", "sk": "SK", "ca": "ES", "hr": "HR",
  ]

  /// Converts a podcast language code (e.g., "zh-tw") to a Locale.
  ///
  /// - "zh-tw" → `Locale(identifier: "zh_TW")`
  /// - "en-us" → `Locale(identifier: "en_US")`
  /// - "en"    → `Locale(identifier: "en_US")` (default region)
  /// - "ja"    → `Locale(identifier: "ja_JP")` (default region)
  public nonisolated static func locale(fromPodcastLanguage languageCode: String) -> Locale {
    let parts = languageCode.lowercased().split(separator: "-")
    switch parts.count {
    case 2:
      return Locale(identifier: "\(parts[0])_\(parts[1].uppercased())")
    case 1:
      let language = String(parts[0])
      if let region = defaultRegions[language] {
        return Locale(identifier: "\(language)_\(region)")
      }
      return Locale(identifier: language)
    default:
      return Locale(identifier: languageCode)
    }
  }
}
