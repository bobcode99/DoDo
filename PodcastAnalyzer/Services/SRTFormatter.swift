//
//  SRTFormatter.swift
//  PodcastAnalyzer
//
//  Extracted from TranscriptService.swift
//

import Foundation
import Speech

@available(iOS 26.0, *)
nonisolated enum SRTFormatter {

  /// Formats a TimeInterval into SRT time format (HH:MM:SS,mmm)
  static func formatTime(_ timeInterval: TimeInterval) -> String {
    let ms = Int(timeInterval.truncatingRemainder(dividingBy: 1) * 1000)
    let s = Int(timeInterval) % 60
    let m = (Int(timeInterval) / 60) % 60
    let h = Int(timeInterval) / 60 / 60
    return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
  }

  /// NaN-safe SRT time formatter.
  /// Clamps non-finite values to 0 to prevent `Int(Double.nan)` crashes.
  static func formatTimeSafe(_ timeInterval: TimeInterval) -> String {
    let safeTime = timeInterval.isFinite ? max(timeInterval, 0) : 0
    return formatTime(safeTime)
  }

  /// Converts transcript segments (with audioTimeRange attributes) into SRT format.
  static func format(segments: [AttributedString]) -> String {
    let srtEntries = segments.enumerated().compactMap { index, segment -> String? in
      guard let timeRange = segment.audioTimeRange else { return nil }

      let text = String(segment.characters).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }

      let entryNumber = index + 1
      let startTime = formatTime(timeRange.start.seconds)
      let endTime = formatTime(timeRange.end.seconds)

      return "\(entryNumber)\n\(startTime) --> \(endTime)\n\(text)"
    }

    return srtEntries.joined(separator: "\n\n")
  }

  /// Converts merged ChunkSegments into SRT format.
  /// Uses `formatTimeSafe` to guard against NaN/infinity values.
  static func format(chunkSegments: [ChunkedTranscriptionService.ChunkSegment]) -> String {
    let srtEntries = chunkSegments.enumerated().map { index, segment -> String in
      let entryNumber = index + 1
      let startTime = formatTimeSafe(segment.startTime)
      let endTime = formatTimeSafe(segment.endTime)
      return "\(entryNumber)\n\(startTime) --> \(endTime)\n\(segment.text)"
    }
    return srtEntries.joined(separator: "\n\n")
  }
}
