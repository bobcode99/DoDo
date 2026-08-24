//
//  SRTParserTests.swift
//  PodcastAnalyzerTests
//
//  SRT is the app's single stored transcript format: host-provided VTT is
//  converted to it, Whisper and Apple Speech both write it, and every reader
//  (caption overlay, transcript page, AI context builder) goes through
//  `parseSegments`. A parser that silently drops the last cue, or that leaves
//  `&#39;` in the text, produces a transcript that looks fine until the exact
//  moment it doesn't — so the failure modes covered here are the ones that
//  reach the user as missing or mangled captions.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("SRT parsing")
struct SRTParserTests {

    // MARK: - Segments

    @Test("A well-formed file parses into segments with timings and text")
    func parsesWellFormedFile() {
        let srt = """
        1
        00:00:00,000 --> 00:00:02,500
        Hello there.

        2
        00:00:02,500 --> 00:00:05,000
        This is a podcast.

        """

        let segments = SRTParser.parseSegments(from: srt)

        #expect(segments.map(\.id) == [1, 2])
        #expect(segments.map(\.text) == ["Hello there.", "This is a podcast."])
        #expect(segments.map(\.startTime) == [0, 2.5])
        #expect(segments.map(\.endTime) == [2.5, 5])
    }

    @Test("The final cue survives a file with no trailing blank line")
    func keepsLastSegmentWithoutTrailingNewline() {
        let srt = """
        1
        00:00:00,000 --> 00:00:01,000
        First.

        2
        00:00:01,000 --> 00:00:02,000
        Last.
        """

        let segments = SRTParser.parseSegments(from: srt)
        #expect(segments.count == 2)
        #expect(segments.last?.text == "Last.")
    }

    @Test("Multi-line cue text is joined into one segment")
    func joinsMultiLineCueText() {
        let srt = """
        1
        00:00:00,000 --> 00:00:04,000
        A sentence that was
        wrapped across two lines.

        """

        #expect(SRTParser.parseSegments(from: srt).map(\.text)
                == ["A sentence that was wrapped across two lines."])
    }

    @Test("CJK cue lines are joined without inserting a space")
    func joinsCJKWithoutSpace() {
        let srt = """
        1
        00:00:00,000 --> 00:00:04,000
        今天我們要談
        關於播客的事情

        """

        #expect(SRTParser.parseSegments(from: srt).map(\.text) == ["今天我們要談關於播客的事情"])
    }

    @Test("Timestamps with a period separator parse the same as commas")
    func acceptsPeriodSeparatedMilliseconds() {
        let srt = """
        1
        00:01:30.250 --> 00:01:32.750
        Period separator.

        """

        let segments = SRTParser.parseSegments(from: srt)
        #expect(segments.map(\.startTime) == [90.25])
        #expect(segments.map(\.endTime) == [92.75])
    }

    @Test("Hours are carried into the offset, not dropped")
    func parsesHours() {
        let srt = """
        1
        01:02:03,000 --> 01:02:04,000
        Deep into a long show.

        """

        #expect(SRTParser.parseSegments(from: srt).first?.startTime == 3723)
    }

    @Test("Empty input yields no segments rather than a phantom one")
    func emptyInput() {
        #expect(SRTParser.parseSegments(from: "").isEmpty)
        #expect(SRTParser.parseSegments(from: "\n\n\n").isEmpty)
    }

    @Test("A cue with a timestamp but no text is dropped")
    func dropsTextlessCue() {
        let srt = """
        1
        00:00:00,000 --> 00:00:01,000

        2
        00:00:01,000 --> 00:00:02,000
        Only this one has text.

        """

        #expect(SRTParser.parseSegments(from: srt).map(\.id) == [2])
    }

    @Test("A cue whose timestamp line is malformed keeps a zero timing rather than crashing")
    func malformedTimestampFallsBackToZero() {
        let srt = """
        1
        not-a-timestamp --> also-not-one
        Text still present.

        """

        let segments = SRTParser.parseSegments(from: srt)
        #expect(segments.map(\.startTime) == [0])
        #expect(segments.map(\.endTime) == [0])
    }

    @Test("Garbage that never looks like SRT parses to nothing")
    func garbageInput() {
        #expect(SRTParser.parseSegments(from: "<html><body>404 Not Found</body></html>").isEmpty)
    }

    // MARK: - HTML entities

    @Test("Named and numeric HTML entities are decoded at ingestion")
    func decodesEntitiesInSegments() {
        let srt = """
        1
        00:00:00,000 --> 00:00:01,000
        It&#39;s Tom &amp; Jerry &mdash; &quot;classic&quot;.

        """

        #expect(SRTParser.parseSegments(from: srt).first?.text
                == "It's Tom & Jerry \u{2014} \"classic\".")
    }

    @Test("Entity decoding covers the whole documented table")
    func decodesEntityTable() {
        let decoded = SRTParser.decodeHTMLEntities(
            "&nbsp;&amp;&lt;&gt;&quot;&apos;&#39;&rsquo;&lsquo;&rdquo;&ldquo;&ndash;&mdash;&hellip;&#160;"
        )
        // &quot; then four apostrophe-producing entities, then two closing quotes.
        #expect(decoded == " &<>\"''''\"\"\u{2013}\u{2014}\u{2026} ")
    }

    @Test("A bare ampersand or an unknown entity is left alone")
    func leavesUnknownEntitiesAlone() {
        #expect(SRTParser.decodeHTMLEntities("R&D") == "R&D")
        #expect(SRTParser.decodeHTMLEntities("&notanentity;") == "&notanentity;")
    }

    @Test("A numeric entity outside Unicode is left as written instead of crashing")
    func outOfRangeNumericEntity() {
        // 0xD800 is a lone surrogate: `Unicode.Scalar(_:)` returns nil for it.
        #expect(SRTParser.decodeHTMLEntities("&#55296;") == "&#55296;")
    }

    // MARK: - Plain text

    @Test("Plain-text extraction drops indices and timings but keeps every line")
    func extractsPlainText() {
        let srt = """
        1
        00:00:00,000 --> 00:00:02,000
        First line.

        2
        00:00:02,000 --> 00:00:04,000
        Second line.

        """

        #expect(SRTParser.extractPlainText(from: srt) == "First line. Second line.")
    }

    @Test("Plain-text extraction of an empty file is empty")
    func extractsNothingFromEmpty() {
        #expect(SRTParser.extractPlainText(from: "").isEmpty)
    }

    // MARK: - Serialization

    @Test("Serializing then parsing returns the same timings and text")
    func roundTrips() {
        let original = [
            TranscriptSegment(id: 1, startTime: 0, endTime: 2.5, text: "Hello there."),
            TranscriptSegment(id: 2, startTime: 3723.125, endTime: 3725, text: "Much later."),
        ]

        let reparsed = SRTParser.parseSegments(from: SRTParser.serialize(segments: original))

        #expect(reparsed.map(\.text) == ["Hello there.", "Much later."])
        #expect(reparsed.map(\.startTime) == [0, 3723.125])
    }

    @Test("Serialized cues are renumbered from one regardless of segment ids")
    func serializeRenumbers() {
        let segments = [
            TranscriptSegment(id: 42, startTime: 0, endTime: 1, text: "A"),
            TranscriptSegment(id: 99, startTime: 1, endTime: 2, text: "B"),
        ]
        let srt = SRTParser.serialize(segments: segments)
        #expect(srt.hasPrefix("1\n"))
        #expect(srt.contains("\n2\n"))
    }

    @Test("Serializing nothing produces an empty document")
    func serializeEmpty() {
        #expect(SRTParser.serialize(segments: []).isEmpty)
    }

    // MARK: - Token estimation

    @Test("Latin text estimates at about four characters per token")
    func estimatesLatinTokens() {
        #expect(SRTParser.estimateTokenCount(for: String(repeating: "a", count: 400)) == 100)
    }

    @Test("CJK text estimates denser, since a character carries more meaning")
    func estimatesCJKTokens() {
        let text = String(repeating: "字", count: 300)
        #expect(SRTParser.estimateTokenCount(for: text, language: "zh") == 200)
        // The region suffix must not change the class of the language.
        #expect(SRTParser.estimateTokenCount(for: text, language: "zh-Hant") == 200)
        #expect(SRTParser.estimateTokenCount(for: text, language: "JA") == 200)
    }

    @Test("An empty string costs no tokens")
    func estimatesEmpty() {
        #expect(SRTParser.estimateTokenCount(for: "") == 0)
    }

    @Test("The estimate rounds up, so one character is never free")
    func estimateRoundsUp() {
        #expect(SRTParser.estimateTokenCount(for: "a") == 1)
    }

    // MARK: - Range extraction

    @Test("Text extraction over a segment range is inclusive at both ends")
    func extractsTextInRange() {
        let segments = [
            TranscriptSegment(id: 1, startTime: 0, endTime: 1, text: "One"),
            TranscriptSegment(id: 2, startTime: 1, endTime: 2, text: "Two"),
            TranscriptSegment(id: 3, startTime: 2, endTime: 3, text: "Three"),
        ]

        #expect(TranscriptSegment.getText(from: segments, startIndex: 1, endIndex: 2) == "One Two")
        #expect(TranscriptSegment.getText(from: segments, startIndex: 2, endIndex: 2) == "Two")
        #expect(TranscriptSegment.getText(from: segments, startIndex: 5, endIndex: 9).isEmpty)
    }
}
