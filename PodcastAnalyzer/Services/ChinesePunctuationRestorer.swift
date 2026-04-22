//
//  ChinesePunctuationRestorer.swift
//  PodcastAnalyzer
//
//  Rule-based punctuation insertion for CJK transcripts.
//  Apple's Speech framework does not auto-insert punctuation for Chinese.
//  Uses audio time gaps between runs as the primary signal.
//

import Foundation
import Speech

@available(iOS 26.0, *)
nonisolated struct ChinesePunctuationRestorer {

  // MARK: - Configuration

  /// Minimum gap (seconds) between runs to insert a comma (，)
  var commaThreshold: Double = 0.3

  /// Minimum gap (seconds) between runs to insert a period (。)
  var periodThreshold: Double = 0.6

  // MARK: - Private Types

  struct RunInfo {
    let range: Range<AttributedString.Index>
    let text: String
    let startTime: Double
    let endTime: Double
  }

  // MARK: - Private Constants

  /// Question-ending particles that turn a period into a question mark
  private static let questionParticles: [String] = [
    "嗎", "吗", "呢", "吧", "嘛", "么",
    "對不對", "对不对",
    "是不是", "好不好",
    "對吧", "对吧",
    "不是嗎", "不是吗",
  ]

  /// Sentence-ending punctuation already present — skip insertion if found
  private static let existingTerminators: Set<Character> = [
    "。", "？", "！", ".", "?", "!",
    "，", "、", "；", "：",
    ",", ";",
  ]

  // MARK: - Public API

  /// Restores punctuation in a CJK AttributedString using audio time gaps.
  ///
  /// Strategy:
  /// 1. Walk runs in order, tracking the end-time of the previous run.
  /// 2. When the gap between the previous run's end and the current run's start
  ///    exceeds a threshold, insert punctuation after the previous run.
  /// 3. Post-process: replace trailing 。 with ？ if the text ends with a question particle.
  func restore(transcript: AttributedString) -> AttributedString {
    var runs: [RunInfo] = []
    for run in transcript.runs {
      let text = String(transcript[run.range].characters)
      guard let timeRange = run.audioTimeRange else { continue }
      let start = timeRange.start.seconds
      let end = timeRange.end.seconds
      guard start.isFinite && end.isFinite else { continue }
      runs.append(RunInfo(range: run.range, text: text, startTime: start, endTime: end))
    }

    guard runs.count >= 2 else { return transcript }

    var insertions: [(afterIndex: AttributedString.Index, punctuation: String)] = []

    for i in 0..<(runs.count - 1) {
      let currentRun = runs[i]
      let nextRun = runs[i + 1]

      let gap = nextRun.startTime - currentRun.endTime
      guard gap >= commaThreshold else { continue }

      let trimmed = currentRun.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if let lastChar = trimmed.last, Self.existingTerminators.contains(lastChar) {
        continue
      }

      let punctuation: String
      if gap >= periodThreshold {
        let accumulatedText = accumulateText(runs: runs, through: i)
        punctuation = isQuestionEnding(accumulatedText) ? "？" : "。"
      } else {
        punctuation = "，"
      }

      insertions.append((afterIndex: currentRun.range.upperBound, punctuation: punctuation))
    }

    guard !insertions.isEmpty else { return transcript }

    var result = AttributedString()
    var lastCopiedUpTo = transcript.startIndex

    for insertion in insertions {
      if lastCopiedUpTo < insertion.afterIndex {
        result += transcript[lastCopiedUpTo..<insertion.afterIndex]
      }
      result += AttributedString(insertion.punctuation)
      lastCopiedUpTo = insertion.afterIndex
    }

    if lastCopiedUpTo < transcript.endIndex {
      result += transcript[lastCopiedUpTo..<transcript.endIndex]
    }

    return result
  }

  // MARK: - Private Helpers

  private func accumulateText(runs: [RunInfo], through index: Int) -> String {
    let start = max(0, index - 5)
    return runs[start...index].map(\.text).joined()
  }

  private func isQuestionEnding(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return Self.questionParticles.contains { trimmed.hasSuffix($0) }
  }
}
