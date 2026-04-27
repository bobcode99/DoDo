//
//  SentenceHighlightTests.swift
//  PodcastAnalyzerTests
//
//  Tests for the unified sentence-block grouping and per-segment highlight
//  derivation used by the transcript view.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

// MARK: - Helper

private func makeSegment(id: Int, start: TimeInterval, end: TimeInterval, text: String) -> TranscriptSegment {
    TranscriptSegment(id: id, startTime: start, endTime: end, text: text)
}

// MARK: - Sentence Grouping

@MainActor
struct SentenceGroupingTests {

    @Test func englishSplitsOnPunctuation() {
        let segments = [
            makeSegment(id: 0, start: 0, end: 2.58, text: "This BBC podcast is supported by ads"),
            makeSegment(id: 1, start: 2.58, end: 3.899, text: "outside the UK."),
            makeSegment(id: 2, start: 3.96, end: 7.86, text: "If journalism is the 1st draft of"),
            makeSegment(id: 3, start: 7.86, end: 8.279, text: "history."),
            makeSegment(id: 4, start: 8.339, end: 10.619, text: "What happens if that draft is flawed?"),
        ]

        let sentences = TranscriptGrouping.groupIntoSentences(segments)

        #expect(sentences.count == 3)
        #expect(sentences[0].segments.count == 2)
        #expect(sentences[0].text == "This BBC podcast is supported by ads outside the UK.")
        #expect(sentences[1].segments.count == 2)
        #expect(sentences[1].text == "If journalism is the 1st draft of history.")
        #expect(sentences[2].segments.count == 1)
    }

    @Test func chineseSplitsOnIdeographicPunctuation() {
        let segments = [
            makeSegment(id: 10, start: 0, end: 2, text: "这个BBC播客"),
            makeSegment(id: 11, start: 2, end: 4, text: "在英国以外有广告。"),
            makeSegment(id: 12, start: 4, end: 6, text: "如果新闻是历史的"),
            makeSegment(id: 13, start: 6, end: 8, text: "第一稿。"),
        ]

        let sentences = TranscriptGrouping.groupIntoSentences(segments)

        #expect(sentences.count == 2)
        #expect(sentences[0].text == "这个BBC播客在英国以外有广告。")
        #expect(sentences[1].text == "如果新闻是历史的第一稿。")
    }

    @Test func timeGapForcesBreak() {
        // Two segments with a > 2 s gap — must split even mid-sentence.
        let segments = [
            makeSegment(id: 0, start: 0, end: 2, text: "before the break"),
            makeSegment(id: 1, start: 6, end: 8, text: "after the break"),
        ]

        let sentences = TranscriptGrouping.groupIntoSentences(segments)

        #expect(sentences.count == 2)
        #expect(sentences[0].segments.count == 1)
        #expect(sentences[1].segments.count == 1)
    }

    @Test func latinSoftCapSplitsLongRun() {
        // Each segment is 30 chars of Latin text without punctuation.
        // Cap is 80 → after segment 3 the running total reaches 90 ≥ 80 → split.
        let chunk = String(repeating: "a", count: 30)
        let segments = (0..<5).map {
            makeSegment(id: $0, start: Double($0), end: Double($0) + 0.5, text: chunk)
        }

        let sentences = TranscriptGrouping.groupIntoSentences(segments)

        #expect(sentences.count >= 2)
        // First sentence triggers cap at the 3rd segment.
        #expect(sentences[0].segments.count == 3)
    }

    @Test func cjkSoftCapSplitsLongRun() {
        // 10 CJK chars per segment, no punctuation. Cap 30 → split after 3 segments.
        let chunk = String(repeating: "字", count: 10)
        let segments = (0..<5).map {
            makeSegment(id: $0, start: Double($0), end: Double($0) + 0.5, text: chunk)
        }

        let sentences = TranscriptGrouping.groupIntoSentences(segments)

        #expect(sentences.count >= 2)
        #expect(sentences[0].segments.count == 3)
    }

    @Test func sentenceIDIsFirstSegmentID() {
        let segments = [
            makeSegment(id: 7, start: 0, end: 1, text: "Hello"),
            makeSegment(id: 8, start: 1, end: 2, text: "world."),
            makeSegment(id: 9, start: 2, end: 3, text: "Next."),
        ]

        let sentences = TranscriptGrouping.groupIntoSentences(segments)

        #expect(sentences[0].id == 7)
        #expect(sentences[0].id == sentences[0].segments.first?.id)
        #expect(sentences[1].id == 9)
    }
}

// MARK: - Active Segment Derivation

@MainActor
struct SentenceActiveSegmentTests {

    private func makeSentence() -> TranscriptSentence {
        TranscriptSentence(id: 0, segments: [
            makeSegment(id: 0, start: 0, end: 2.58, text: "This BBC podcast is supported by ads"),
            makeSegment(id: 1, start: 2.58, end: 3.899, text: "outside the UK."),
        ])
    }

    @Test func returnsNilBeforeStart() {
        let sentence = makeSentence()
        #expect(sentence.activeSegmentIndex(at: -1) == nil)
    }

    @Test func returnsFirstWhileInsideFirstSegment() {
        let sentence = makeSentence()
        #expect(sentence.activeSegmentIndex(at: 1.0) == 0)
    }

    @Test func returnsSecondAtSecondStart() {
        let sentence = makeSentence()
        #expect(sentence.activeSegmentIndex(at: 2.58) == 1)
        #expect(sentence.activeSegmentIndex(at: 3.0) == 1)
    }

    @Test func returnsLastIndexAfterEnd() {
        // Last-started semantics: once past the last segment's startTime, it
        // remains the active index until a higher-level selector chooses a
        // different sentence.
        let sentence = makeSentence()
        #expect(sentence.activeSegmentIndex(at: 5.0) == 1)
    }
}

// MARK: - CJK Joining

@MainActor
struct SentenceTextJoiningTests {

    @Test func englishJoinedWithSpaces() {
        let sentence = TranscriptSentence(id: 0, segments: [
            makeSegment(id: 0, start: 0, end: 2, text: "This is"),
            makeSegment(id: 1, start: 2, end: 4, text: "a test."),
        ])
        #expect(sentence.text == "This is a test.")
    }

    @Test func chineseJoinedWithoutSpaces() {
        let sentence = TranscriptSentence(id: 0, segments: [
            makeSegment(id: 0, start: 0, end: 2, text: "这个"),
            makeSegment(id: 1, start: 2, end: 4, text: "函数"),
            makeSegment(id: 2, start: 4, end: 6, text: "有问题。"),
        ])
        #expect(sentence.text == "这个函数有问题。")
    }

    @Test func japaneseJoinedWithoutSpaces() {
        let sentence = TranscriptSentence(id: 0, segments: [
            makeSegment(id: 0, start: 0, end: 2, text: "これは"),
            makeSegment(id: 1, start: 2, end: 4, text: "テストです。"),
        ])
        #expect(sentence.text == "これはテストです。")
    }
}

// MARK: - Segment Link

@MainActor
struct TranscriptSegmentLinkTests {

    @Test func segmentURLRoundTripsSegmentID() throws {
        let segment = makeSegment(id: 42, start: 12.34, end: 15.67, text: "jump here")

        let url = try #require(TranscriptSegmentLink.url(for: segment))
        let segmentID = TranscriptSegmentLink.segmentID(from: url)

        #expect(url.absoluteString == "pa-transcript-segment://42")
        #expect(segmentID == 42)
    }

    @Test func rejectsOtherURLSchemes() throws {
        let url = try #require(URL(string: "https://example.com/42"))

        #expect(TranscriptSegmentLink.segmentID(from: url) == nil)
    }
}
