//
//  AnalysisResponseParsingTests.swift
//  PodcastAnalyzerTests
//
//  An episode analysis that finishes but shows nothing is indistinguishable
//  from a hang. Every case here previously produced exactly that: the decode
//  failed, the raw reply was discarded at the persistence boundary, and the
//  tab sat on "Done — 100% complete" with an empty body.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@Suite("Cloud analysis response parsing")
struct AnalysisResponseParsingTests {

    private func decode(_ raw: String) -> ParsedEpisodeAnalysisResponse? {
        CloudAIService.decodeJSON(raw, as: ParsedEpisodeAnalysisResponse.self)
    }

    @Test("plain JSON object decodes")
    func plainObject() throws {
        let parsed = try #require(decode(#"{"overview":"An episode.","conclusion":"Done."}"#))
        #expect(parsed.overview == "An episode.")
        #expect(parsed.isEmpty == false)
    }

    @Test("prose wrapped around the object still decodes")
    func proseWrapped() throws {
        let raw = """
        Sure! Here is the analysis you asked for:
        {"overview":"An episode.","conclusion":"Done."}
        Let me know if you want more detail.
        """
        let parsed = try #require(decode(raw))
        #expect(parsed.overview == "An episode.")
    }

    @Test("fence that starts mid-response still decodes")
    func fencedMidResponse() throws {
        let raw = """
        Here you go:

        ```json
        {"overview":"An episode.","conclusion":"Done."}
        ```
        """
        let parsed = try #require(decode(raw))
        #expect(parsed.conclusion == "Done.")
    }

    @Test("braces inside string values do not end the object early")
    func bracesInsideStrings() throws {
        let raw = #"noise {"overview":"He said {this} out loud","conclusion":"End"} trailing"#
        let parsed = try #require(decode(raw))
        #expect(parsed.overview == "He said {this} out loud")
        #expect(parsed.conclusion == "End")
    }

    @Test("a missing section does not discard the sections that arrived")
    func partialSectionsSurvive() throws {
        // No mainTopics, no conclusion — both used to be hard-required, so the
        // whole response was thrown away.
        let parsed = try #require(decode(#"{"overview":"An episode.","keyTakeaways":["one","two"]}"#))
        #expect(parsed.keyTakeaways == ["one", "two"])
        #expect(parsed.mainTopics.isEmpty)
        #expect(parsed.conclusion.isEmpty)
        #expect(parsed.isEmpty == false)
    }

    @Test("valid JSON of the wrong shape reports as empty, not as a result")
    func wrongShapeIsEmpty() throws {
        let parsed = try #require(decode(#"{"summary":"wrong key names entirely"}"#))
        #expect(parsed.isEmpty, "an all-default decode must be treated as a parse miss")
    }

    @Test("truncated JSON yields no result so the raw text is used instead")
    func truncatedYieldsNil() {
        #expect(decode(#"{"overview":"An episode.","keyTakeaways":["one","tw"#) == nil)
    }
}
