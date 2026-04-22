//
//  TranscriptSegmenter.swift
//  PodcastAnalyzer
//
//  Extracted from TranscriptService.swift — text segmentation logic.
//

import Foundation
import NaturalLanguage
import Speech

/// Word-level timing data for a single word
@available(iOS 26.0, *)
public nonisolated struct WordTimingData: Codable, Sendable {
  public let word: String
  public let startTime: Double
  public let endTime: Double
}

/// Segment data with word-level timing information
@available(iOS 26.0, *)
public nonisolated struct SegmentData: Codable, Sendable {
  public let id: Int
  public let startTime: Double
  public let endTime: Double
  public let text: String
  public let wordTimings: [WordTimingData]
}

/// Transcript data containing segments with word timings
@available(iOS 26.0, *)
public nonisolated struct TranscriptData: Codable, Sendable {
  public let segments: [SegmentData]
}

@available(iOS 26.0, *)
nonisolated struct TranscriptSegmenter {
  let isCJK: Bool
  let maxLength: Int

  /// CJK clause-level punctuation used as secondary split points.
  /// These are natural pause points in speech that make good subtitle breaks.
  static let clauseMarkers: Set<Character> = [
    "，", "、", "；", "：",  // Fullwidth CJK punctuation
    ",", ";",              // ASCII equivalents sometimes used
  ]

  // MARK: - Public API

  /// Computes segment ranges for the transcript.
  /// For CJK locales, applies clause-level splitting (，、；：) before word-level fallback.
  func computeSegmentRanges(
    transcript: AttributedString
  ) -> [Range<AttributedString.Index>] {
    let string = String(transcript.characters)
    let tokenizer = NLTokenizer(unit: .sentence)
    tokenizer.string = string

    let sentenceRanges = tokenizer.tokens(for: string.startIndex..<string.endIndex).compactMap {
      stringRange -> (Range<String.Index>, Range<AttributedString.Index>)? in
      guard
        let attrLower = AttributedString.Index(stringRange.lowerBound, within: transcript),
        let attrUpper = AttributedString.Index(stringRange.upperBound, within: transcript)
      else { return nil }
      return (stringRange, attrLower..<attrUpper)
    }

    return sentenceRanges.flatMap {
      sentenceStringRange, sentenceAttrRange -> [Range<AttributedString.Index>] in
      let sentence = transcript[sentenceAttrRange]

      guard sentence.characters.count > maxLength else {
        return [sentenceAttrRange]
      }

      if isCJK {
        // CJK: split at clause markers first, then word-split oversized clauses
        let clauseRanges = splitAtClauseMarkers(
          stringRange: sentenceStringRange,
          attrRange: sentenceAttrRange,
          transcript: transcript,
          string: string
        )

        var result: [Range<AttributedString.Index>] = []
        for (clauseStringRange, clauseAttrRange) in clauseRanges {
          let clauseLen = transcript[clauseAttrRange].characters.count

          if clauseLen > maxLength {
            // Clause itself is too long (no punctuation), fall back to word splitting
            result.append(contentsOf: splitByWords(
              stringRange: clauseStringRange,
              attrRange: clauseAttrRange,
              transcript: transcript,
              string: string
            ))
          } else if let lastRange = result.last,
            transcript[lastRange].characters.count + clauseLen <= maxLength
          {
            // Merge small adjacent clauses into one segment
            result[result.count - 1] = lastRange.lowerBound..<clauseAttrRange.upperBound
          } else {
            result.append(clauseAttrRange)
          }
        }
        return result
      } else {
        // Non-CJK: split by words directly
        return splitByWords(
          stringRange: sentenceStringRange,
          attrRange: sentenceAttrRange,
          transcript: transcript,
          string: string
        )
      }
    }
  }

  /// Splits transcript into segments with proper time ranges for SRT generation.
  func splitTranscriptIntoSegments(
    transcript: AttributedString
  ) -> [AttributedString] {
    let allRanges = computeSegmentRanges(transcript: transcript)

    return allRanges.compactMap { range -> AttributedString? in
      let segment = transcript[range]

      let audioTimeRanges = segment.runs.filter {
        !String(transcript[$0.range].characters)
          .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }.compactMap(\.audioTimeRange)

      guard let firstTimeRange = audioTimeRanges.first,
        let lastTimeRange = audioTimeRanges.last
      else { return nil }

      let start = firstTimeRange.start
      let end = lastTimeRange.end

      var attributes = AttributeContainer()
      attributes[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = CMTimeRange(
        start: start,
        end: end
      )
      return AttributedString(segment.characters, attributes: attributes)
    }
  }

  /// Extracts segments with word-level timing from the transcript
  func extractSegmentsWithWordTimings(
    transcript: AttributedString
  ) -> [SegmentData] {
    let allRanges = computeSegmentRanges(transcript: transcript)

    return allRanges.enumerated().compactMap { index, range -> SegmentData? in
      let segment = transcript[range]
      let segmentText = String(segment.characters).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !segmentText.isEmpty else { return nil }

      // Extract word timings from runs
      var wordTimings: [WordTimingData] = []
      for run in segment.runs {
        let wordText = String(transcript[run.range].characters)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wordText.isEmpty, let timeRange = run.audioTimeRange else { continue }

        wordTimings.append(WordTimingData(
          word: wordText,
          startTime: timeRange.start.seconds,
          endTime: timeRange.end.seconds
        ))
      }

      guard let firstTiming = wordTimings.first,
            let lastTiming = wordTimings.last else { return nil }

      return SegmentData(
        id: index + 1,
        startTime: firstTiming.startTime,
        endTime: lastTiming.endTime,
        text: segmentText,
        wordTimings: wordTimings
      )
    }
  }

  // MARK: - Private Helpers

  /// Splits a text range at CJK clause markers (，、；：).
  /// Each clause includes its trailing marker character.
  private func splitAtClauseMarkers(
    stringRange: Range<String.Index>,
    attrRange: Range<AttributedString.Index>,
    transcript: AttributedString,
    string: String
  ) -> [(Range<String.Index>, Range<AttributedString.Index>)] {
    var result: [(Range<String.Index>, Range<AttributedString.Index>)] = []
    var clauseStart = stringRange.lowerBound

    var idx = stringRange.lowerBound
    while idx < stringRange.upperBound {
      let char = string[idx]
      let nextIdx = string.index(after: idx)

      if Self.clauseMarkers.contains(char) {
        guard
          let attrLower = AttributedString.Index(clauseStart, within: transcript),
          let attrUpper = AttributedString.Index(nextIdx, within: transcript)
        else {
          idx = nextIdx
          continue
        }
        result.append((clauseStart..<nextIdx, attrLower..<attrUpper))
        clauseStart = nextIdx
      }
      idx = nextIdx
    }

    // Add remaining text after last marker
    if clauseStart < stringRange.upperBound {
      if let attrLower = AttributedString.Index(clauseStart, within: transcript),
        let attrUpper = AttributedString.Index(stringRange.upperBound, within: transcript)
      {
        result.append((clauseStart..<stringRange.upperBound, attrLower..<attrUpper))
      }
    }

    return result
  }

  /// Splits a text range by word boundaries, accumulating words up to maxLength.
  private func splitByWords(
    stringRange: Range<String.Index>,
    attrRange: Range<AttributedString.Index>,
    transcript: AttributedString,
    string: String
  ) -> [Range<AttributedString.Index>] {
    let wordTokenizer = NLTokenizer(unit: .word)
    wordTokenizer.string = string

    var wordRanges: [Range<AttributedString.Index>] = wordTokenizer.tokens(
      for: stringRange
    ).compactMap { wordStringRange -> Range<AttributedString.Index>? in
      guard
        let attrLower = AttributedString.Index(wordStringRange.lowerBound, within: transcript),
        let attrUpper = AttributedString.Index(wordStringRange.upperBound, within: transcript)
      else { return nil }
      return attrLower..<attrUpper
    }

    guard !wordRanges.isEmpty else { return [attrRange] }

    // Extend first/last words to cover leading/trailing whitespace and punctuation
    wordRanges[0] = attrRange.lowerBound..<wordRanges[0].upperBound
    wordRanges[wordRanges.count - 1] =
      wordRanges[wordRanges.count - 1].lowerBound..<attrRange.upperBound

    // Accumulate words into segments respecting maxLength
    var segmentRanges: [Range<AttributedString.Index>] = []
    for wordRange in wordRanges {
      if let lastRange = segmentRanges.last,
        transcript[lastRange].characters.count + transcript[wordRange].characters.count
          <= maxLength
      {
        segmentRanges[segmentRanges.count - 1] = lastRange.lowerBound..<wordRange.upperBound
      } else {
        segmentRanges.append(wordRange)
      }
    }

    return segmentRanges
  }

  /// Helper to check for sentence endings in various languages
  func isSentenceEnd(_ text: String) -> Bool {
    let terminators: Set<Character> = [".", "!", "?", "。", "！", "？"]
    guard let lastChar = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
      return false
    }
    return terminators.contains(lastChar)
  }
}
