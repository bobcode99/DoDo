//
//  SRTFormatterTests.swift
//  PodcastAnalyzerTests
//
//  Apple Speech hands back audio time ranges that are sometimes NaN, and
//  `Int(Double.nan)` traps rather than returning anything — so an unguarded
//  formatter crashes the app at the end of a transcription the user just waited
//  ten minutes for. `formatTimeSafe` is the guard; these tests are what keep it
//  from being "simplified" back into `formatTime`.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("SRT time formatting")
struct SRTFormatterTests {

    // MARK: - Well-formed times

    @Test("A time is rendered as HH:MM:SS,mmm with every field padded")
    func formatsPaddedFields() {
        #expect(SRTFormatter.formatTime(0) == "00:00:00,000")
        #expect(SRTFormatter.formatTime(5.25) == "00:00:05,250")
        #expect(SRTFormatter.formatTime(61) == "00:01:01,000")
        #expect(SRTFormatter.formatTime(3661.5) == "01:01:01,500")
    }

    @Test("Times past a day keep counting hours rather than wrapping")
    func doesNotWrapAtTwentyFourHours() {
        #expect(SRTFormatter.formatTime(90_061) == "25:01:01,000")
    }

    @Test("The safe formatter agrees with the plain one on ordinary input",
          arguments: [0.0, 5.25, 61.0, 3661.5, 90_061.0])
    func safeMatchesPlainForFiniteTimes(_ time: TimeInterval) {
        #expect(SRTFormatter.formatTimeSafe(time) == SRTFormatter.formatTime(time))
    }

    // MARK: - The values that trap

    @Test("NaN and infinity are clamped to zero instead of trapping")
    func clampsNonFiniteTimes() {
        #expect(SRTFormatter.formatTimeSafe(.nan) == "00:00:00,000")
        #expect(SRTFormatter.formatTimeSafe(.infinity) == "00:00:00,000")
        #expect(SRTFormatter.formatTimeSafe(-.infinity) == "00:00:00,000")
        #expect(SRTFormatter.formatTimeSafe(.signalingNaN) == "00:00:00,000")
    }

    @Test("A negative time floors at zero rather than emitting a negative cue")
    func clampsNegativeTimes() {
        #expect(SRTFormatter.formatTimeSafe(-1) == "00:00:00,000")
        #expect(SRTFormatter.formatTimeSafe(-0.5) == "00:00:00,000")
    }

    // MARK: - Chunk segments

    private func chunk(_ start: Double, _ end: Double, _ text: String)
    -> ChunkedTranscriptionService.ChunkSegment {
        ChunkedTranscriptionService.ChunkSegment(startTime: start, endTime: end, text: text)
    }

    @Test("Merged chunk segments become a numbered SRT document")
    func formatsChunkSegments() {
        let srt = SRTFormatter.format(chunkSegments: [
            chunk(0, 2, "First."),
            chunk(2, 4.5, "Second."),
        ])

        #expect(srt == """
        1
        00:00:00,000 --> 00:00:02,000
        First.

        2
        00:00:02,000 --> 00:00:04,500
        Second.
        """)
    }

    @Test("A chunk carrying NaN timings still produces a parseable document")
    func formatsChunkSegmentsWithBadTimings() {
        let srt = SRTFormatter.format(chunkSegments: [
            chunk(.nan, .nan, "Recovered."),
            chunk(2, 4, "Fine."),
        ])

        let reparsed = SRTParser.parseSegments(from: srt)
        #expect(reparsed.map(\.text) == ["Recovered.", "Fine."])
        #expect(reparsed.map(\.startTime) == [0, 2])
    }

    @Test("No segments produce an empty document, not a stray cue number")
    func formatsNoChunkSegments() {
        #expect(SRTFormatter.format(chunkSegments: []).isEmpty)
    }

    @Test("Chunk output is renumbered from one and reads back through the SRT parser")
    func chunkOutputRoundTrips() {
        let srt = SRTFormatter.format(chunkSegments: [
            chunk(0, 1, "One"),
            chunk(1, 2, "Two"),
            chunk(2, 3, "Three"),
        ])

        let reparsed = SRTParser.parseSegments(from: srt)
        #expect(reparsed.map(\.id) == [1, 2, 3])
        #expect(reparsed.map(\.text) == ["One", "Two", "Three"])
    }
}
