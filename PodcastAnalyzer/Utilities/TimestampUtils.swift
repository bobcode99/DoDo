//
//  TimestampUtils.swift
//  PodcastAnalyzer
//
//  Timestamp parsing and formatting utilities for AI analysis views.
//

import Foundation
import SwiftUI

nonisolated struct TimestampUtils {

  /// Parses a timestamp string like "05:32", "1:23:45", or "[05:32]" into total seconds.
  static func parseToSeconds(_ timestamp: String) -> TimeInterval? {
    // Strip brackets if present
    let cleaned = timestamp
      .trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: "[", with: "")
      .replacingOccurrences(of: "]", with: "")

    let parts = cleaned.split(separator: ":").compactMap { Int($0) }
    switch parts.count {
    case 2:
      // MM:SS
      return TimeInterval(parts[0] * 60 + parts[1])
    case 3:
      // H:MM:SS or HH:MM:SS
      return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
    default:
      return nil
    }
  }

  /// Finds all timestamps in a text string. Returns deduplicated results.
  static func findTimestamps(in text: String) -> [(text: String, seconds: TimeInterval)] {
    guard let regex = try? NSRegularExpression(
      pattern: #"(?<!\d)(\d{1,2}:\d{2}(?::\d{2})?)(?!\d)"#
    ) else { return [] }

    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex.matches(in: text, range: nsRange)

    var seen = Set<String>()
    var results: [(text: String, seconds: TimeInterval)] = []

    for match in matches {
      guard let range = Range(match.range(at: 1), in: text) else { continue }
      let matched = String(text[range])
      guard !seen.contains(matched), let seconds = parseToSeconds(matched) else { continue }
      // Skip 0:00 / 00:00 / 00:00:00
      guard seconds > 0 else { continue }
      seen.insert(matched)
      results.append((text: matched, seconds: seconds))
    }

    return results
  }

  /// Formats seconds into a display string like "05:32" or "1:23:45".
  static func formatSeconds(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
      return String(format: "%02d:%02d", minutes, secs)
    }
  }

  /// Custom URL scheme used for inline tappable timestamps.
  static let urlScheme = "pa-timestamp"

  /// Adds clickable timestamp links to an `AttributedString`.
  /// Timestamps are rendered as blue underlined text using SwiftUI-native attributes.
  static func addTimestampLinks(to source: AttributedString) -> AttributedString {
    var attributed = source
    let text = String(attributed.characters)
    guard let regex = try? NSRegularExpression(
      pattern: #"(?<!\d)(\d{1,2}:\d{2}(?::\d{2})?)(?!\d)"#
    ) else { return attributed }

    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex.matches(in: text, range: nsRange)

    for match in matches {
      guard let swiftRange = Range(match.range(at: 1), in: text) else { continue }
      let matched = String(text[swiftRange])
      guard let seconds = parseToSeconds(matched), seconds > 0,
            let attrRange = Range(swiftRange, in: attributed) else { continue }
      attributed[attrRange].link = URL(string: "\(urlScheme)://\(Int(seconds))")
      attributed[attrRange].underlineStyle = Text.LineStyle(pattern: .solid)
      attributed[attrRange].foregroundColor = .blue
    }
    return attributed
  }

  /// Adds link attributes to timestamps in a plain string, returning an AttributedString.
  static func attributedStringWithTimestampLinks(_ text: String) -> AttributedString {
    addTimestampLinks(to: AttributedString(text))
  }

  /// Parses a `pa-timestamp://` URL, returning seconds if valid.
  static func parseTimestampURL(_ url: URL) -> TimeInterval? {
    guard url.scheme == urlScheme, let host = url.host(), let seconds = Int(host) else {
      return nil
    }
    return TimeInterval(seconds)
  }
}
