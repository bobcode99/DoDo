//
//  JSONTranscriptParserTests.swift
//  PodcastAnalyzerTests
//
//  Hosts publish Podcasting 2.0 JSON transcripts with one segment per word, so
//  the parser merges them into readable cues. A cue must break on speaker change
//  and sentence end, or every row becomes one word or one wall of text.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("JSON transcript parsing")
struct JSONTranscriptParserTests {

    private func srt(_ json: String) throws -> [TranscriptSegment] {
        let content = try #require(JSONTranscriptParser.convertToSRT(Data(json.utf8)))
        return SRTParser.parseSegments(from: content)
    }

    @Test("Per-word segments merge into one cue per sentence")
    func mergesWords() throws {
        let segments = try srt("""
        {"version":"1.0.0","segments":[
          {"speaker":"Alice","startTime":0.0,"endTime":0.4,"body":"Hello"},
          {"speaker":"Alice","startTime":0.4,"endTime":0.9,"body":"there."},
          {"speaker":"Alice","startTime":1.0,"endTime":1.5,"body":"Welcome"},
          {"speaker":"Alice","startTime":1.5,"endTime":2.0,"body":"back."}
        ]}
        """)

        #expect(segments.map(\.text) == ["Hello there.", "Welcome back."])
        #expect(segments.first?.startTime == 0)
        #expect(segments.last?.endTime == 2)
    }

    @Test("A speaker change starts a new cue")
    func splitsOnSpeaker() throws {
        let segments = try srt("""
        {"segments":[
          {"speaker":"Alice","startTime":0,"endTime":1,"body":"Hi"},
          {"speaker":"Bob","startTime":1,"endTime":2,"body":"Hey"}
        ]}
        """)

        #expect(segments.map(\.text) == ["Hi", "Hey"])
    }

    @Test("Non-transcript JSON is rejected")
    func rejectsGarbage() {
        #expect(JSONTranscriptParser.convertToSRT(Data(#"{"foo":1}"#.utf8)) == nil)
    }
}
