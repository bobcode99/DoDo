//
//  JSONTranscriptParser.swift
//  PodcastAnalyzer
//
//  Utility for parsing Podcasting 2.0 JSON transcript files
//  Reference: https://github.com/Podcastindex-org/podcast-namespace/blob/main/docs/examples/transcripts/transcripts.md
//

import Foundation

/// Converts a Podcasting 2.0 JSON transcript to SRT.
///
/// Hosts often emit one segment per word, so consecutive segments from the same
/// speaker are merged into cues that end at sentence punctuation, a speaker
/// change, a pause, or a length cap.
nonisolated struct JSONTranscriptParser: Sendable {

  private struct Document: Decodable {
    let segments: [Segment]
  }

  private struct Segment: Decodable {
    let speaker: String?
    let startTime: TimeInterval
    let endTime: TimeInterval
    let body: String
  }

  private static let maxCueDuration: TimeInterval = 10
  private static let maxGap: TimeInterval = 1.5

  /// - Returns: SRT content, or nil if the data isn't a JSON transcript.
  nonisolated static func convertToSRT(_ data: Data) -> String? {
    guard let document = try? JSONDecoder().decode(Document.self, from: data) else { return nil }

    var cues: [(start: TimeInterval, end: TimeInterval, text: String)] = []
    var current: (start: TimeInterval, end: TimeInterval, text: String, speaker: String?)?

    for segment in document.segments {
      let body = segment.body.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !body.isEmpty else { continue }

      if let cue = current,
         cue.speaker == segment.speaker,
         segment.startTime - cue.end <= maxGap,
         segment.endTime - cue.start <= maxCueDuration,
         !endsSentence(cue.text) {
        current?.end = segment.endTime
        current?.text = CJKTextUtils.joinTexts([cue.text, body])
      } else {
        if let cue = current { cues.append((cue.start, cue.end, cue.text)) }
        current = (segment.startTime, segment.endTime, body, segment.speaker)
      }
    }
    if let cue = current { cues.append((cue.start, cue.end, cue.text)) }

    return cues.enumerated().map { index, cue in
      "\(index + 1)\n\(formatSRTTime(cue.start)) --> \(formatSRTTime(cue.end))\n\(cue.text)\n"
    }.joined(separator: "\n")
  }

  private nonisolated static func endsSentence(_ text: String) -> Bool {
    guard let last = text.last else { return false }
    return ".!?。！？".contains(last)
  }

  private nonisolated static func formatSRTTime(_ time: TimeInterval) -> String {
    let hours = Int(time) / 3600
    let minutes = (Int(time) % 3600) / 60
    let seconds = Int(time) % 60
    let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
    return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
  }
}
