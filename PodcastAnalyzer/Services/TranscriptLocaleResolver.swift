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
  /// "zh" defaults to Mainland Mandarin (CN) — most podcast feeds that omit a
  /// region are Simplified/Mainland shows, and Apple's zh_CN and zh_TW are
  /// separate acoustic + vocabulary models, not just a script difference.
  /// Getting this wrong measurably hurts word-level accuracy, not just script.
  private nonisolated static let defaultRegions: [String: String] = [
    "en": "US", "zh": "CN", "ja": "JP", "ko": "KR",
    "fr": "FR", "de": "DE", "es": "ES", "it": "IT",
    "pt": "BR", "ru": "RU", "ar": "SA", "hi": "IN",
    "th": "TH", "vi": "VN", "id": "ID", "ms": "MY",
    "nl": "NL", "pl": "PL", "tr": "TR", "uk": "UA",
    "cs": "CZ", "el": "GR", "he": "IL", "ro": "RO",
    "hu": "HU", "sv": "SE", "da": "DK", "fi": "FI",
    "nb": "NO", "sk": "SK", "ca": "ES", "hr": "HR",
  ]

  /// Script-subtag → region mapping. Some feeds tag language as e.g. "zh-Hans"
  /// (script) instead of "zh-CN" (region); treating the subtag as a region
  /// verbatim produces an invalid Locale ("zh_HANS") that matches no Speech
  /// asset. Map known script subtags onto the region carrying that script.
  private nonisolated static let scriptSubtagRegions: [String: [String: String]] = [
    "zh": ["hans": "CN", "hant": "TW"]
  ]

  /// Converts a podcast language code (e.g., "zh-tw") to a Locale.
  ///
  /// - "zh-tw"   → `Locale(identifier: "zh_TW")`
  /// - "zh-hans" → `Locale(identifier: "zh_CN")` (script subtag, not region)
  /// - "en-us"   → `Locale(identifier: "en_US")`
  /// - "en"      → `Locale(identifier: "en_US")` (default region)
  /// - "zh"      → `Locale(identifier: "zh_CN")` (default region)
  public nonisolated static func locale(fromPodcastLanguage languageCode: String) -> Locale {
    let parts = languageCode.lowercased().split(separator: "-")
    switch parts.count {
    case 2:
      let language = String(parts[0])
      let second = String(parts[1])
      if let region = scriptSubtagRegions[language]?[second] {
        return Locale(identifier: "\(language)_\(region)")
      }
      return Locale(identifier: "\(language)_\(second.uppercased())")
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
