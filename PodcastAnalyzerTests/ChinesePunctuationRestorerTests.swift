//
//  ChinesePunctuationRestorerTests.swift
//  PodcastAnalyzerTests
//
//  Apple's Speech framework inserts no punctuation for Chinese, so a transcript
//  arrives as one unbroken wall of characters. This restorer infers the breaks
//  from the pauses in the audio — the only signal available — and gets them
//  wrong in two ways that matter: punctuating where the speaker did not pause
//  (a comma mid-word), and doubling punctuation the recognizer already emitted.
//
//  Runs are built with real `CMTimeRange` attributes, the same shape the Speech
//  framework hands back, so the gap arithmetic is exercised for real.
//

import CoreMedia
import Foundation
import Speech
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Chinese punctuation restoration")
struct ChinesePunctuationRestorerTests {

    /// Builds a transcript of timed runs, the way Speech returns one.
    private func transcript(_ runs: [(text: String, start: Double, end: Double)])
    -> AttributedString {
        var result = AttributedString()
        for run in runs {
            var attributes = AttributeContainer()
            attributes[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = CMTimeRange(
                start: CMTime(seconds: run.start, preferredTimescale: 600),
                end: CMTime(seconds: run.end, preferredTimescale: 600)
            )
            result += AttributedString(run.text, attributes: attributes)
        }
        return result
    }

    private func restored(
        _ runs: [(text: String, start: Double, end: Double)],
        comma: Double = 0.3,
        period: Double = 0.6
    ) -> String {
        var restorer = ChinesePunctuationRestorer()
        restorer.commaThreshold = comma
        restorer.periodThreshold = period
        return String(restorer.restore(transcript: transcript(runs)).characters)
    }

    // MARK: - Gap thresholds

    @Test("A short pause becomes a comma")
    func shortPauseBecomesComma() {
        let result = restored([
            ("今天我們要談播客", 0, 2.0),
            ("這是第一集", 2.4, 4.0),
        ])

        #expect(result == "今天我們要談播客，這是第一集")
    }

    @Test("A long pause becomes a full stop")
    func longPauseBecomesPeriod() {
        let result = restored([
            ("今天我們要談播客", 0, 2.0),
            ("這是第一集", 2.8, 4.0),
        ])

        #expect(result == "今天我們要談播客。這是第一集")
    }

    @Test("Speech with no real pause in it is left alone")
    func noPauseNoPunctuation() {
        let result = restored([
            ("今天我們", 0, 2.0),
            ("要談播客", 2.1, 4.0),
        ])

        #expect(result == "今天我們要談播客")
    }

    @Test("A pause exactly at a threshold counts as that threshold")
    func thresholdsAreInclusive() {
        #expect(restored([("好的", 0, 1.0), ("繼續", 1.3, 2.0)]) == "好的，繼續")
        #expect(restored([("好的", 0, 1.0), ("繼續", 1.6, 2.0)]) == "好的。繼續")
    }

    @Test("The thresholds are configurable, and a stricter one punctuates less")
    func thresholdsAreConfigurable() {
        let runs = [("好的", 0.0, 1.0), ("繼續", 1.4, 2.0)]

        #expect(restored(runs) == "好的，繼續")
        #expect(restored(runs, comma: 2.0, period: 3.0) == "好的繼續")
    }

    // MARK: - Questions

    @Test("A question particle before a long pause ends the sentence with a question mark")
    func questionParticleBecomesQuestionMark() {
        let result = restored([
            ("你今天有空嗎", 0, 2.0),
            ("我們可以聊聊", 2.8, 4.0),
        ])

        #expect(result == "你今天有空嗎？我們可以聊聊")
    }

    @Test("Simplified and Traditional particles are both recognised")
    func recognisesBothScripts() {
        #expect(restored([("你有空吗", 0, 2.0), ("好的", 2.8, 3.5)]) == "你有空吗？好的")
        #expect(restored([("是不是", 0, 2.0), ("好的", 2.8, 3.5)]) == "是不是？好的")
    }

    @Test("A question particle before only a short pause still gets a comma, not a question mark")
    func questionParticleNeedsASentenceBreak() {
        #expect(restored([("你有空嗎", 0, 2.0), ("我想問", 2.4, 3.5)]) == "你有空嗎，我想問")
    }

    @Test("A statement ending in an ordinary character gets a full stop")
    func statementGetsPeriod() {
        #expect(restored([("我明白了", 0, 2.0), ("我們繼續", 2.8, 3.5)]) == "我明白了。我們繼續")
    }

    // MARK: - Punctuation already present

    @Test("Punctuation the recognizer already emitted is not doubled")
    func doesNotDoublePunctuation() {
        let result = restored([
            ("今天我們要談播客。", 0, 2.0),
            ("這是第一集", 2.8, 4.0),
        ])

        #expect(result == "今天我們要談播客。這是第一集")
    }

    @Test("An existing comma also blocks insertion")
    func existingCommaBlocksInsertion() {
        #expect(restored([("好的，", 0, 1.0), ("繼續", 1.4, 2.0)]) == "好的，繼續")
    }

    @Test("Trailing whitespace doesn't hide the punctuation already there")
    func trailingWhitespaceDoesNotHidePunctuation() {
        #expect(restored([("好的。 ", 0, 1.0), ("繼續", 1.8, 2.0)]) == "好的。 繼續")
    }

    // MARK: - Degenerate input

    @Test("A transcript of one run has no gap to punctuate")
    func singleRunIsUnchanged() {
        #expect(restored([("今天我們要談播客", 0, 2.0)]) == "今天我們要談播客")
    }

    @Test("An empty transcript comes back empty")
    func emptyTranscriptIsUnchanged() {
        var restorer = ChinesePunctuationRestorer()
        let result = restorer.restore(transcript: AttributedString())
        #expect(String(result.characters).isEmpty)

        // Silence the "never mutated" warning while keeping the value type.
        restorer.commaThreshold = 0.3
    }

    @Test("Text with no timing information is returned untouched")
    func untimedTextIsUnchanged() {
        let restorer = ChinesePunctuationRestorer()
        let plain = AttributedString("今天我們要談播客這是第一集")
        #expect(String(restorer.restore(transcript: plain).characters)
                == "今天我們要談播客這是第一集")
    }

    @Test("Non-finite timings are skipped rather than producing punctuation from garbage")
    func skipsNonFiniteTimings() {
        var attributes = AttributeContainer()
        attributes[AttributeScopes.SpeechAttributes.TimeRangeAttribute.self] = CMTimeRange(
            start: CMTime(value: 0, timescale: 0),  // invalid → NaN seconds
            end: CMTime(value: 0, timescale: 0)
        )
        var text = AttributedString("今天", attributes: attributes)
        text += AttributedString("我們")

        let restorer = ChinesePunctuationRestorer()
        #expect(String(restorer.restore(transcript: text).characters) == "今天我們")
    }

    // MARK: - Content preservation

    @Test("Restoration only adds punctuation — no character of speech is lost or reordered")
    func speechIsPreserved() {
        let runs = [
            ("今天我們要談播客", 0.0, 2.0),
            ("這是第一集", 2.8, 4.0),
            ("希望你喜歡", 4.4, 6.0),
            ("下週見", 6.9, 8.0),
        ]

        let result = restored(runs)
        let inserted = CharacterSet(charactersIn: "，。？")
        let stripped = result.components(separatedBy: inserted).joined()

        #expect(stripped == runs.map(\.0).joined())
        #expect(result.count > stripped.count)
    }

    @Test("Every gap that qualifies gets exactly one mark")
    func oneMarkPerQualifyingGap() {
        let result = restored([
            ("第一句", 0.0, 1.0),
            ("第二句", 1.8, 2.5),   // long gap → 。
            ("第三句", 2.9, 3.5),   // short gap → ，
            ("第四句", 3.55, 4.0),  // no gap → nothing
        ])

        #expect(result == "第一句。第二句，第三句第四句")
    }
}
