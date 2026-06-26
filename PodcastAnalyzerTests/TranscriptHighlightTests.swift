//
//  TranscriptHighlightTests.swift
//  PodcastAnalyzerTests
//
//  Validates the "which sentence/segment is currently playing" logic that
//  drives the transcript highlight + auto-scroll. These are pure functions
//  with no audio/UI dependencies — fast, deterministic, parallel-safe.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Transcript highlighting")
struct TranscriptHighlightTests {

    // MARK: - Fixtures

    private func seg(
        _ id: Int,
        start: TimeInterval,
        end: TimeInterval,
        text: String = "x"
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: id,
            startTime: start,
            endTime: end,
            text: text,
            translatedText: nil,
            wordTimings: nil
        )
    }

    /// Three contiguous sentences: [0..10], [10..20], [20..30].
    private func threeSentences() -> [TranscriptSentence] {
        [
            TranscriptSentence(id: 0, segments: [seg(0, start: 0, end: 10)]),
            TranscriptSentence(id: 10, segments: [seg(10, start: 10, end: 20)]),
            TranscriptSentence(id: 20, segments: [seg(20, start: 20, end: 30)]),
        ]
    }

    // MARK: - Sentence-level: activeID(at:)

    @Test("Empty transcript never highlights")
    func emptyTranscriptHasNoActive() {
        let sentences: [TranscriptSentence] = []
        #expect(sentences.activeID(at: 0) == nil)
        #expect(sentences.activeID(at: 100) == nil)
    }

    @Test("Time before the first sentence starts returns nil")
    func timeBeforeFirstSentenceReturnsNil() {
        let sentences = [
            TranscriptSentence(id: 0, segments: [seg(0, start: 5, end: 10)])
        ]
        #expect(sentences.activeID(at: 0) == nil)
        #expect(sentences.activeID(at: 4.999) == nil)
    }

    @Test("Exact start boundary picks that sentence (inclusive)")
    func exactStartBoundaryIsInclusive() {
        let sentences = threeSentences()
        #expect(sentences.activeID(at: 0) == 0)
        #expect(sentences.activeID(at: 10) == 10)
        #expect(sentences.activeID(at: 20) == 20)
    }

    @Test("Within a sentence keeps that sentence active")
    func withinSentenceStaysActive() {
        let sentences = threeSentences()
        #expect(sentences.activeID(at: 5) == 0)
        #expect(sentences.activeID(at: 15) == 10)
        #expect(sentences.activeID(at: 25) == 20)
    }

    @Test("Time past the last sentence keeps it highlighted (last-started)")
    func pastEndStillHighlightsLast() {
        let sentences = threeSentences()
        #expect(sentences.activeID(at: 30) == 20)
        #expect(sentences.activeID(at: 999) == 20)
    }

    @Test("Gap between sentences holds the previous sentence (last-started)")
    func gapHoldsPreviousSentence() {
        // [0..5] then [10..15] — at t=7 nothing is being spoken, but the
        // last sentence to have started is sentence 0.
        let sentences = [
            TranscriptSentence(id: 0, segments: [seg(0, start: 0, end: 5)]),
            TranscriptSentence(id: 10, segments: [seg(10, start: 10, end: 15)]),
        ]
        #expect(sentences.activeID(at: 7) == 0)
        #expect(sentences.activeID(at: 9.999) == 0)
        #expect(sentences.activeID(at: 10) == 10)
    }

    @Test(
        "Binary search agrees with a linear last-started oracle at many times",
        arguments: [
            -1.0, 0.0, 0.001, 1.2, 2.4, 2.5, 5.0, 8.0, 10.0, 12.1,
            16.7, 22.5, 31.7, 55.5, 100.0, 100.5, 1_000.0,
        ] as [TimeInterval]
    )
    func binarySearchMatchesLinearOracle(time: TimeInterval) {
        // 20 sentences with strictly increasing, non-uniform start times.
        let starts: [TimeInterval] = [
            0, 1.2, 2.5, 4.0, 5.3, 6.8, 8.2, 10.0, 12.1, 14.4,
            16.7, 19.0, 22.5, 25.0, 28.3, 31.7, 40.0, 55.5, 78.0, 100.0,
        ]
        let sentences = starts.enumerated().map { i, s in
            TranscriptSentence(id: i, segments: [seg(i, start: s, end: s + 1)])
        }
        let oracle = sentences.last { $0.startTime <= time }?.id
        #expect(sentences.activeID(at: time) == oracle)
    }

    // MARK: - Segment-level: TranscriptSentence.activeSegmentIndex(at:)

    @Test("Single-segment sentence is its own active segment from its start onward")
    func singleSegmentSentence() {
        let sentence = TranscriptSentence(id: 0, segments: [seg(0, start: 0, end: 5)])
        #expect(sentence.activeSegmentIndex(at: 0) == 0)
        #expect(sentence.activeSegmentIndex(at: 2.5) == 0)
        #expect(sentence.activeSegmentIndex(at: 5) == 0)
        #expect(sentence.activeSegmentIndex(at: 100) == 0)
    }

    @Test("Multi-segment sentence advances using last-started semantics")
    func multiSegmentLastStarted() {
        let sentence = TranscriptSentence(id: 0, segments: [
            seg(0, start: 0, end: 1),
            seg(1, start: 1, end: 2),
            seg(2, start: 2, end: 3),
            seg(3, start: 3, end: 4),
        ])
        #expect(sentence.activeSegmentIndex(at: 0) == 0)
        #expect(sentence.activeSegmentIndex(at: 0.999) == 0)
        #expect(sentence.activeSegmentIndex(at: 1.0) == 1)
        #expect(sentence.activeSegmentIndex(at: 2.5) == 2)
        #expect(sentence.activeSegmentIndex(at: 3.999) == 3)
        #expect(sentence.activeSegmentIndex(at: 1_000) == 3)
    }

    @Test("Time before the sentence's first segment returns nil")
    func timeBeforeFirstSegmentReturnsNil() {
        let sentence = TranscriptSentence(id: 5, segments: [
            seg(5, start: 5, end: 6),
            seg(6, start: 6, end: 7),
        ])
        #expect(sentence.activeSegmentIndex(at: 0) == nil)
        #expect(sentence.activeSegmentIndex(at: 4.999) == nil)
        #expect(sentence.activeSegmentIndex(at: 5) == 0)
    }

    // MARK: - Producer precondition

    /// `activeID(at:)` is a binary search and only returns the correct answer
    /// when sentences are sorted by `startTime`. The grouping algorithm is the
    /// sole producer of sentence arrays in the app, so this test pins the
    /// contract: grouping must emit strictly time-sorted sentences.
    @Test("Grouping emits strictly increasing sentence start times")
    func groupingIsTimeSorted() throws {
        let segments = (0..<50).map { i in
            // ~17 sentences: a sentence-ending period every 3rd segment.
            seg(
                i,
                start: TimeInterval(i),
                end: TimeInterval(i + 1),
                text: i % 3 == 2 ? "end." : "word"
            )
        }
        let sentences = TranscriptGrouping.groupIntoSentences(segments)
        try #require(sentences.count >= 2)
        for i in 1..<sentences.count {
            #expect(sentences[i].startTime > sentences[i - 1].startTime)
        }
    }

    // MARK: - Music marker isolation

    /// A `[♪ Music]` segment between speech segments must form its own
    /// sentence — never get concatenated with neighbouring speech.
    @Test("Music marker between speech becomes its own sentence")
    func musicMarkerStandsAlone() throws {
        let segments = [
            seg(0, start: 0, end: 1, text: "Hello world"),
            seg(1, start: 1, end: 4, text: MusicDetectionService.markerText),
            seg(2, start: 4, end: 5, text: "After music"),
        ]
        let sentences = TranscriptGrouping.groupIntoSentences(segments)
        try #require(sentences.count == 3)
        #expect(sentences[0].text == "Hello world")
        #expect(sentences[1].text == MusicDetectionService.markerText)
        #expect(sentences[2].text == "After music")
    }

    @Test("Music marker at the start of the transcript stands alone")
    func markerAtStartStandsAlone() throws {
        let segments = [
            seg(0, start: 0, end: 3, text: MusicDetectionService.markerText),
            seg(1, start: 3, end: 4, text: "Hello"),
        ]
        let sentences = TranscriptGrouping.groupIntoSentences(segments)
        try #require(sentences.count == 2)
        #expect(sentences[0].text == MusicDetectionService.markerText)
        #expect(sentences[1].text == "Hello")
    }

    @Test("Consecutive music markers each become their own sentence")
    func consecutiveMarkers() throws {
        let segments = [
            seg(0, start: 0, end: 3, text: MusicDetectionService.markerText),
            seg(1, start: 3, end: 6, text: MusicDetectionService.markerText),
        ]
        let sentences = TranscriptGrouping.groupIntoSentences(segments)
        #expect(sentences.count == 2)
    }

    // MARK: - annotateMusicSegments boundary preservation

    /// The old midpoint-only filter dropped real speech when its midpoint
    /// happened to land inside a music range — for example a host who starts
    /// talking before the intro music tag fully ends. The new overlap-ratio
    /// filter keeps speech whose majority is outside the music range.
    @Test("Speech crossing a music boundary survives annotation")
    func speechCrossingMusicBoundarySurvives() {
        let speech = [
            ChunkedTranscriptionService.ChunkSegment(
                startTime: 9.0, endTime: 13.0,
                text: "Welcome back to the show"
            )
        ]
        let musicRanges = [
            MusicDetectionService.TimeRange(start: 8.0, end: 11.0)
        ]
        // 2s of the 4s segment overlaps music → ratio 0.5, below 0.7 default.
        let result = ChunkedTranscriptionService.annotateMusicSegments(
            speechSegments: speech, musicRanges: musicRanges
        )
        #expect(result.contains { $0.text == "Welcome back to the show" })
        #expect(result.contains { $0.text == MusicDetectionService.markerText })
    }

    @Test("Speech entirely inside music is replaced by the marker")
    func speechFullyInsideMusicIsDropped() {
        let speech = [
            ChunkedTranscriptionService.ChunkSegment(
                startTime: 10.0, endTime: 11.0, text: "garble"
            )
        ]
        let musicRanges = [
            MusicDetectionService.TimeRange(start: 8.0, end: 15.0)
        ]
        let result = ChunkedTranscriptionService.annotateMusicSegments(
            speechSegments: speech, musicRanges: musicRanges
        )
        #expect(!result.contains { $0.text == "garble" })
        #expect(result.contains { $0.text == MusicDetectionService.markerText })
    }

    @Test("Empty music ranges leaves speech segments untouched")
    func emptyMusicRangesPassthrough() {
        let speech = [
            ChunkedTranscriptionService.ChunkSegment(
                startTime: 0, endTime: 1, text: "Hello"
            )
        ]
        let result = ChunkedTranscriptionService.annotateMusicSegments(
            speechSegments: speech, musicRanges: []
        )
        #expect(result.count == 1)
        #expect(result[0].text == "Hello")
    }

    // MARK: - Chunked merge dedup

    private func makeChunk(
        index: Int, start: TimeInterval, end: TimeInterval
    ) -> ChunkedTranscriptionService.AudioChunk {
        ChunkedTranscriptionService.AudioChunk(
            index: index,
            fileURL: URL(fileURLWithPath: "/tmp/chunk_\(index).m4a"),
            startTime: start,
            endTime: end
        )
    }

    private func makeChunkSeg(
        _ start: TimeInterval, _ end: TimeInterval, _ text: String
    ) -> ChunkedTranscriptionService.ChunkSegment {
        ChunkedTranscriptionService.ChunkSegment(
            startTime: start, endTime: end, text: text
        )
    }

    /// The classic timestamp-accuracy bug: speech crosses a chunk boundary and
    /// the previous chunk transcribed all the way to its file's end. The old
    /// dedup keyed off the previous chunk's *last segment* endTime, leaving
    /// chunk N+1's overlap-region segments in the merged output and producing
    /// duplicate words. The fix keys off the previous chunk's *nominal* end.
    @Test("Merge drops overlap-region segments from later chunks")
    func mergeDropsOverlapDuplicates() {
        let chunks = [
            makeChunk(index: 0, start: 0, end: 60),
            makeChunk(index: 1, start: 58, end: 118),
        ]
        let chunkResults = [
            [
                makeChunkSeg(5, 58, "Hello how are you"),
            ],
            [
                // Chunk 1 retranscribed the [58, 60] overlap — must be dropped.
                makeChunkSeg(58, 60, "are you doing"),
                // First post-boundary segment — must be kept.
                makeChunkSeg(60, 62, "today and tomorrow"),
            ],
        ]
        let merged = ChunkedTranscriptionService.mergeChunkSegments(
            chunkResults, chunks: chunks
        )
        #expect(merged.map(\.text) == ["Hello how are you", "today and tomorrow"])
    }

    @Test("Merge keeps a single chunk's results unchanged")
    func mergeSingleChunkPassthrough() {
        let chunks = [makeChunk(index: 0, start: 0, end: 30)]
        let chunkResults = [[
            makeChunkSeg(0, 5, "alpha"),
            makeChunkSeg(5, 10, "beta"),
        ]]
        let merged = ChunkedTranscriptionService.mergeChunkSegments(
            chunkResults, chunks: chunks
        )
        #expect(merged.map(\.text) == ["alpha", "beta"])
    }

    @Test("Merge cutoff is exactly chunk N's nominal end (inclusive on N+1)")
    func mergeCutoffIsInclusive() {
        let chunks = [
            makeChunk(index: 0, start: 0, end: 60),
            makeChunk(index: 1, start: 58, end: 118),
        ]
        let chunkResults = [
            [makeChunkSeg(0, 5, "early")],
            [
                makeChunkSeg(59.999, 60.5, "drop"),   // before 60 → dropped
                makeChunkSeg(60.0, 61.0, "keep"),     // at 60 → kept (>=)
            ],
        ]
        let merged = ChunkedTranscriptionService.mergeChunkSegments(
            chunkResults, chunks: chunks
        )
        #expect(merged.map(\.text) == ["early", "keep"])
    }
}
