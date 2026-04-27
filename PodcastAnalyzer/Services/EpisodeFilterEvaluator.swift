//
//  EpisodeFilterEvaluator.swift
//  PodcastAnalyzer
//
//  Pure value-type filter logic that matches AntennaPod's episode auto-download
//  decision order exactly (guide §8).
//

import Foundation

struct EpisodeFilterEvaluator {

  /// Decides whether an episode should be auto-downloaded.
  ///
  /// Decision order (matches AntennaPod §8):
  /// 1. Reject if duration is known AND shorter than the minimum.
  /// 2. Reject if the title contains any excluded term.
  /// 3. Accept if the title contains any included term.
  /// 4. If only the exclude filter is set (include is empty) and no excluded term
  ///    matched → accept (the episode survived the exclusion filter).
  /// 5. If only min-duration is set (both term filters empty) and the episode
  ///    passed step 1 → accept.
  /// 6. Default: if the include filter is non-empty and nothing matched → reject.
  nonisolated static func shouldAutoDownload(
    episodeTitle: String,
    durationSeconds: TimeInterval,  // 0 = unknown
    includeFilter: String,
    excludeFilter: String,
    minDurationSeconds: Int
  ) -> Bool {
    let includeTerms = parseTerms(includeFilter)
    let excludeTerms = parseTerms(excludeFilter)
    let hasInclude = !includeTerms.isEmpty
    let hasExclude = !excludeTerms.isEmpty
    let hasMinDuration = minDurationSeconds > 0

    // If no filters are configured at all, always accept.
    if !hasInclude && !hasExclude && !hasMinDuration {
      return true
    }

    let lowerTitle = episodeTitle.localizedLowercase

    // Step 1 — duration gate (only when duration is known).
    if hasMinDuration && durationSeconds > 0 && durationSeconds < TimeInterval(minDurationSeconds) {
      return false
    }

    // Step 2 — exclude gate.
    if hasExclude {
      for term in excludeTerms where lowerTitle.localizedStandardContains(term) {
        return false
      }
    }

    // Step 3 — include gate.
    if hasInclude {
      for term in includeTerms where lowerTitle.localizedStandardContains(term) {
        return true
      }
    }

    // Step 4 — only exclude filter exists and no excluded term matched → accept.
    if hasExclude && !hasInclude {
      return true
    }

    // Step 5 — only min-duration filter exists and episode passed step 1 → accept.
    if hasMinDuration && !hasInclude && !hasExclude {
      return true
    }

    // Step 6 — include filter exists but nothing matched → reject.
    return false
  }

  /// Parses `"term1, \"multi word\", term3"` into `["term1", "multi word", "term3"]`.
  /// Splits on commas, trims whitespace, strips surrounding double-quotes, lowercases.
  nonisolated static func parseTerms(_ raw: String) -> [String] {
    guard !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
    return raw.split(separator: ",", omittingEmptySubsequences: true)
      .compactMap { component -> String? in
        var trimmed = component.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 {
          trimmed = String(trimmed.dropFirst().dropLast())
        }
        let cleaned = trimmed.trimmingCharacters(in: .whitespaces).localizedLowercase
        return cleaned.isEmpty ? nil : cleaned
      }
  }
}
