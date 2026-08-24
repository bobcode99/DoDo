//
//  PodcastNamespaceParserTests.swift
//  PodcastAnalyzerTests
//
//  Podcasting 2.0 tags are the difference between downloading a transcript the
//  publisher already made and spending ten minutes of device time generating a
//  worse one — and between knowing the cast and guessing at "Speaker 1". Both
//  come from a single hand-rolled XML pass over the feed, where the failure mode
//  is silent: a transcript filed under the wrong GUID is a transcript that never
//  loads, and a `<podcast:person>` at channel level credited to an episode is a
//  guest who isn't one.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Podcasting 2.0 namespace parsing")
struct PodcastNamespaceParserTests {

    private let parser = PodcastNamespaceParser()

    private func feed(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:podcast="https://podcastindex.org/namespace/1.0">
          <channel>
            <title>The Show</title>
        \(body)
          </channel>
        </rss>
        """.utf8)
    }

    // MARK: - Transcripts

    @Test("A transcript tag is filed under its episode's GUID with type and language")
    func parsesTranscript() throws {
        let transcripts = parser.parseTranscripts(from: feed("""
            <item>
              <title>Episode One</title>
              <guid>ep-001</guid>
              <podcast:transcript url="https://example.com/ep1.vtt" type="text/vtt" language="en" rel="captions"/>
            </item>
        """))

        let info = try #require(transcripts["ep-001"])
        #expect(info.url == "https://example.com/ep1.vtt")
        #expect(info.type == "text/vtt")
        #expect(info.language == "en")
        #expect(info.rel == "captions")
        #expect(transcripts.count == 1)
    }

    @Test("Each episode keeps its own transcript rather than the last one winning")
    func parsesTranscriptPerEpisode() {
        let transcripts = parser.parseTranscripts(from: feed("""
            <item>
              <title>One</title>
              <guid>ep-001</guid>
              <podcast:transcript url="https://example.com/1.vtt" type="text/vtt"/>
            </item>
            <item>
              <title>Two</title>
              <guid>ep-002</guid>
              <podcast:transcript url="https://example.com/2.vtt" type="text/vtt"/>
            </item>
        """))

        #expect(transcripts.count == 2)
        #expect(transcripts["ep-001"]?.url == "https://example.com/1.vtt")
        #expect(transcripts["ep-002"]?.url == "https://example.com/2.vtt")
    }

    @Test("When a feed offers several formats, a timed one beats plain text")
    func prefersTimedFormats() throws {
        let transcripts = parser.parseTranscripts(from: feed("""
            <item>
              <guid>ep-001</guid>
              <podcast:transcript url="https://example.com/ep1.txt" type="text/plain"/>
              <podcast:transcript url="https://example.com/ep1.srt" type="application/srt"/>
            </item>
        """))

        // Plain text has no timings, so it can't drive caption highlighting.
        #expect(try #require(transcripts["ep-001"]).url == "https://example.com/ep1.srt")
    }

    @Test("A transcript missing its url or type is ignored")
    func ignoresIncompleteTranscriptTags() {
        let transcripts = parser.parseTranscripts(from: feed("""
            <item>
              <guid>ep-001</guid>
              <podcast:transcript type="text/vtt"/>
              <podcast:transcript url="https://example.com/ep1.vtt"/>
            </item>
        """))

        #expect(transcripts.isEmpty)
    }

    @Test("A transcript on an item with no GUID is dropped, since nothing could find it later")
    func requiresAGUID() {
        let transcripts = parser.parseTranscripts(from: feed("""
            <item>
              <title>No GUID Here</title>
              <podcast:transcript url="https://example.com/x.vtt" type="text/vtt"/>
            </item>
        """))

        #expect(transcripts.isEmpty)
    }

    @Test("A channel-level transcript tag is not attributed to any episode")
    func ignoresChannelLevelTranscript() {
        let transcripts = parser.parseTranscripts(from: feed("""
            <podcast:transcript url="https://example.com/show.vtt" type="text/vtt"/>
            <item>
              <guid>ep-001</guid>
            </item>
        """))

        #expect(transcripts.isEmpty)
    }

    @Test("A feed with no Podcasting 2.0 tags yields nothing rather than failing")
    func handlesPlainFeed() {
        let transcripts = parser.parseTranscripts(from: feed("""
            <item>
              <title>Plain Episode</title>
              <guid>ep-001</guid>
              <enclosure url="https://example.com/ep1.mp3" type="audio/mpeg"/>
            </item>
        """))

        #expect(transcripts.isEmpty)
    }

    @Test("Malformed XML parses to nothing instead of throwing or hanging")
    func handlesMalformedXML() {
        #expect(parser.parseTranscripts(from: Data()).isEmpty)
        #expect(parser.parseTranscripts(from: Data("<rss><channel><item>".utf8)).isEmpty)
        #expect(parser.parseTranscripts(from: Data("total nonsense".utf8)).isEmpty)
    }

    // MARK: - People

    @Test("Channel people are the show's cast; item people belong to their episode")
    func separatesShowAndEpisodePeople() throws {
        let data = parser.parse(from: feed("""
            <podcast:person role="host">Alice Fernandez</podcast:person>
            <podcast:person role="producer" group="writing">Dana Ruiz</podcast:person>
            <item>
              <guid>ep-001</guid>
              <podcast:person role="guest">Bob Chen</podcast:person>
            </item>
        """))

        #expect(data.showPeople.map(\.name) == ["Alice Fernandez", "Dana Ruiz"])
        #expect(data.episodePeople["ep-001"]?.map(\.name) == ["Bob Chen"])
        // The guest must not leak into the show's regular cast.
        #expect(data.showPeople.contains { $0.name == "Bob Chen" } == false)
    }

    @Test("Roles and groups are captured lowercased")
    func lowercasesRoleAndGroup() throws {
        let data = parser.parse(from: feed("""
            <podcast:person role="Host" group="Cast">Alice</podcast:person>
        """))

        let person = try #require(data.showPeople.first)
        #expect(person.role == "host")
        #expect(person.group == "cast")
    }

    @Test("A person with no role is a host, per the spec's default")
    func unroledPersonIsHost() throws {
        let data = parser.parse(from: feed("""
            <podcast:person>Alice</podcast:person>
            <podcast:person role="guest">Bob</podcast:person>
        """))

        #expect(try #require(data.showPeople.first).isHost)
        #expect(data.showPeople.last?.isHost == false)
    }

    @Test("A person tag with no name is skipped rather than credited as blank")
    func skipsNamelessPerson() {
        let data = parser.parse(from: feed("""
            <podcast:person role="host">   </podcast:person>
            <podcast:person role="host">Alice</podcast:person>
        """))

        #expect(data.showPeople.map(\.name) == ["Alice"])
    }

    @Test("A name split across the XML stream is reassembled whole")
    func reassemblesSplitNames() {
        // Entities force the parser to deliver the text in several callbacks.
        let data = parser.parse(from: feed("""
            <podcast:person role="host">Tom &amp; Jerry</podcast:person>
        """))

        #expect(data.showPeople.map(\.name) == ["Tom & Jerry"])
    }

    @Test("An episode with no credits is absent from the map, not present and empty")
    func omitsEpisodesWithoutPeople() {
        let data = parser.parse(from: feed("""
            <item>
              <guid>ep-001</guid>
            </item>
        """))

        #expect(data.episodePeople.isEmpty)
    }

    @Test("One pass returns the same transcripts as the transcripts-only pass")
    func singlePassAgreesWithTranscriptPass() {
        let xml = feed("""
            <podcast:person role="host">Alice</podcast:person>
            <item>
              <guid>ep-001</guid>
              <podcast:transcript url="https://example.com/1.vtt" type="text/vtt"/>
              <podcast:person role="guest">Bob</podcast:person>
            </item>
        """)

        let combined = parser.parse(from: xml)
        let transcriptsOnly = parser.parseTranscripts(from: xml)

        #expect(combined.transcripts == transcriptsOnly)
        #expect(combined.showPeople.count == 1)
        #expect(combined.episodePeople["ep-001"]?.count == 1)
    }

    // MARK: - TranscriptInfo helpers

    @Test("MIME types are classified into the formats the app can actually read")
    func classifiesTranscriptTypes() {
        let vtt = TranscriptInfo(url: "https://example.com/a.vtt", type: "text/vtt",
                                 language: nil, rel: nil)
        let srt = TranscriptInfo(url: "https://example.com/a.srt", type: "application/srt",
                                 language: nil, rel: nil)
        let text = TranscriptInfo(url: "https://example.com/a.txt", type: "text/plain",
                                  language: nil, rel: nil)

        #expect(vtt.isVTT)
        #expect(vtt.isSRT == false)
        #expect(srt.isSRT)
        #expect(srt.isVTT == false)
        #expect(text.isPlainText)
        #expect(text.isVTT == false)
    }

    @Test("A transcript URL that isn't a URL comes back nil instead of crashing later")
    func rejectsUnusableURLs() {
        let good = TranscriptInfo(url: "https://example.com/a.vtt", type: "text/vtt",
                                  language: nil, rel: nil)
        let bad = TranscriptInfo(url: "", type: "text/vtt", language: nil, rel: nil)

        #expect(good.urlObject != nil)
        #expect(bad.urlObject?.absoluteString.isEmpty ?? true)
    }
}
