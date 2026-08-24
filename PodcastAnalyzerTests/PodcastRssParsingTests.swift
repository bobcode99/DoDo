//
//  PodcastRssParsingTests.swift
//  PodcastAnalyzerTests
//
//  Every subscription in the app starts as bytes off a stranger's server. Feeds
//  in the wild omit half the optional fields, put the artwork in three different
//  places, and occasionally answer an RSS request with an HTML error page — and
//  a parser that throws on any of that means "Add Feed" simply fails with no
//  explanation the user can act on.
//
//  Parsing is exercised on fixture bytes, never over the network, so these tests
//  are about the decoding rules and nothing else.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("RSS feed parsing")
struct PodcastRssParsingTests {

    private let service = PodcastRssService()
    private let feedURL = "https://example.com/feed.xml"

    private func parse(_ xml: String) async throws -> PodcastInfo {
        try await service.parseRSSPodcast(from: Data(xml.utf8), rssUrl: feedURL)
    }

    private func feed(channel: String = "", items: String = "") -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"
             xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
             xmlns:podcast="https://podcastindex.org/namespace/1.0">
          <channel>
            <title>The Show</title>
            <description>A show about things.</description>
            <language>en-us</language>
            <itunes:author>Example Media</itunes:author>
            <itunes:image href="https://example.com/art.jpg"/>
        \(channel)
        \(items)
          </channel>
        </rss>
        """
    }

    private func item(
        title: String = "Episode 1",
        guid: String = "ep-1",
        audio: String? = "https://example.com/1.mp3",
        extra: String = ""
    ) -> String {
        let enclosure = audio.map {
            #"<enclosure url="\#($0)" type="audio/mpeg" length="1000"/>"#
        } ?? ""
        return """
            <item>
              <title>\(title)</title>
              <description>Episode notes.</description>
              <guid>\(guid)</guid>
              <pubDate>Tue, 12 Nov 2024 10:00:00 +0000</pubDate>
              <itunes:duration>3600</itunes:duration>
              \(enclosure)
        \(extra)
            </item>
        """
    }

    // MARK: - Channel

    @Test("Show metadata is read from the channel")
    func parsesChannelMetadata() async throws {
        let podcast = try await parse(feed(items: item()))

        #expect(podcast.title == "The Show")
        #expect(podcast.podcastInfoDescription == "A show about things.")
        #expect(podcast.language == "en-us")
        #expect(podcast.author == "Example Media")
        #expect(podcast.imageURL == "https://example.com/art.jpg")
        // The feed URL is the show's identity, not anything inside the document.
        #expect(podcast.rssUrl == feedURL)
        #expect(podcast.id == feedURL)
    }

    @Test("A channel with no title still parses, under a placeholder")
    func handlesUntitledChannel() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
          <item><title>Episode 1</title>
            <enclosure url="https://example.com/1.mp3" type="audio/mpeg"/></item>
        </channel></rss>
        """

        let podcast = try await parse(xml)
        #expect(podcast.title == "Untitled Podcast")
        #expect(podcast.episodes.count == 1)
    }

    @Test("Optional channel fields left out come back empty rather than failing the parse")
    func handlesSparseChannel() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel><title>Bare</title></channel></rss>
        """

        let podcast = try await parse(xml)
        #expect(podcast.title == "Bare")
        #expect(podcast.imageURL.isEmpty)
        #expect(podcast.language.isEmpty)
        #expect(podcast.author == nil)
        #expect(podcast.episodes.isEmpty)
    }

    // MARK: - Episodes

    @Test("An episode carries its title, audio, guid, duration and date")
    func parsesEpisode() async throws {
        let podcast = try await parse(feed(items: item()))
        let episode = try #require(podcast.episodes.first)

        #expect(episode.title == "Episode 1")
        #expect(episode.audioURL == "https://example.com/1.mp3")
        #expect(episode.guid == "ep-1")
        #expect(episode.duration == 3600)
        #expect(episode.podcastEpisodeDescription == "Episode notes.")
        #expect(episode.pubDate != nil)
    }

    @Test("Episodes keep the order the feed lists them in")
    func preservesEpisodeOrder() async throws {
        let items = (1...3).map { item(title: "Episode \($0)", guid: "ep-\($0)") }.joined()
        let podcast = try await parse(feed(items: items))

        #expect(podcast.episodes.map(\.title) == ["Episode 1", "Episode 2", "Episode 3"])
    }

    @Test("An item with no title is dropped, since nothing could render it")
    func dropsUntitledItems() async throws {
        let untitled = """
            <item>
              <guid>no-title</guid>
              <enclosure url="https://example.com/x.mp3" type="audio/mpeg"/>
            </item>
        """
        let podcast = try await parse(feed(items: untitled + item()))

        #expect(podcast.episodes.map(\.title) == ["Episode 1"])
    }

    @Test("An item with no enclosure is kept, just without anything to play")
    func keepsItemsWithoutAudio() async throws {
        let podcast = try await parse(feed(items: item(audio: nil)))
        let episode = try #require(podcast.episodes.first)

        #expect(episode.title == "Episode 1")
        #expect(episode.audioURL == nil)
    }

    @Test("An episode with no duration reports none rather than zero")
    func handlesMissingDuration() async throws {
        let noDuration = """
            <item>
              <title>Episode 1</title>
              <enclosure url="https://example.com/1.mp3" type="audio/mpeg"/>
            </item>
        """
        #expect(try await parse(feed(items: noDuration)).episodes.first?.duration == nil)
    }

    @Test("Episode artwork is read when present and left absent when not")
    func parsesEpisodeArtwork() async throws {
        let withArt = item(extra: #"      <itunes:image href="https://example.com/1.jpg"/>"#)

        #expect(try await parse(feed(items: withArt)).episodes.first?.imageURL
                == "https://example.com/1.jpg")
        #expect(try await parse(feed(items: item())).episodes.first?.imageURL == nil)
    }

    // MARK: - Transcripts

    @Test("A VTT transcript tag is attached to its episode")
    func parsesTranscript() async throws {
        let withTranscript = item(
            extra: #"      <podcast:transcript url="https://example.com/1.vtt" type="text/vtt"/>"#)
        let episode = try #require(try await parse(feed(items: withTranscript)).episodes.first)

        #expect(episode.transcriptURL == "https://example.com/1.vtt")
        #expect(episode.transcriptType == "text/vtt")
    }

    @Test("A timed transcript is chosen over a plain-text one")
    func prefersTimedTranscript() async throws {
        let both = item(extra: """
              <podcast:transcript url="https://example.com/1.txt" type="text/plain"/>
              <podcast:transcript url="https://example.com/1.vtt" type="text/vtt"/>
        """)

        #expect(try await parse(feed(items: both)).episodes.first?.transcriptURL
                == "https://example.com/1.vtt")
    }

    @Test("A transcript in a format the app can't read is ignored")
    func ignoresUnsupportedTranscript() async throws {
        let unsupported = item(
            extra: #"      <podcast:transcript url="https://example.com/1.html" type="text/html"/>"#)

        #expect(try await parse(feed(items: unsupported)).episodes.first?.transcriptURL == nil)
    }

    @Test("An episode with no transcript tag simply has none")
    func handlesNoTranscript() async throws {
        #expect(try await parse(feed(items: item())).episodes.first?.transcriptURL == nil)
    }

    // MARK: - People

    @Test("Channel and episode credits are carried onto the parsed show")
    func parsesPeople() async throws {
        let withPeople = feed(
            channel: #"    <podcast:person role="host">Alice Fernandez</podcast:person>"#,
            items: item(
                extra: #"      <podcast:person role="guest">Bob Chen</podcast:person>"#))

        let podcast = try await parse(withPeople)
        #expect(podcast.people.map(\.name) == ["Alice Fernandez"])
        #expect(podcast.episodePeople["ep-1"]?.map(\.name) == ["Bob Chen"])
    }

    @Test("A feed with no credits carries an empty cast, not a decode failure")
    func handlesNoPeople() async throws {
        let podcast = try await parse(feed(items: item()))
        #expect(podcast.people.isEmpty)
        #expect(podcast.episodePeople.isEmpty)
    }

    // MARK: - Failure paths

    @Test("An HTML error page served in place of a feed is reported as a parse failure")
    func rejectsHTMLErrorPage() async {
        await #expect(throws: (any Error).self) {
            try await parse("<html><body><h1>404 Not Found</h1></body></html>")
        }
    }

    @Test("Empty and truncated payloads are rejected rather than parsed into an empty show")
    func rejectsEmptyAndTruncatedPayloads() async {
        await #expect(throws: (any Error).self) {
            try await service.parseRSSPodcast(from: Data(), rssUrl: feedURL)
        }
        await #expect(throws: (any Error).self) {
            try await parse("<?xml version=\"1.0\"?><rss><channel><title>Cut")
        }
    }

    @Test("A feed URL Foundation can't parse is refused before any request is made")
    func rejectsMalformedURL() async throws {
        // The #require is a guard on the test itself: if Foundation ever starts
        // accepting this string, the test fails here rather than quietly turning
        // into a live network call.
        try #require(URL(string: "") == nil)

        await #expect(throws: PodcastServiceError.self) {
            _ = try await service.fetchPodcast(from: "")
        }
    }

    @Test("Each failure explains itself, so the Add Feed sheet has something to show")
    func errorsAreDescribed() {
        #expect(PodcastServiceError.invalidURL.errorDescription?.isEmpty == false)
        #expect(PodcastServiceError.notRSS.errorDescription?.isEmpty == false)
        #expect(PodcastServiceError.parsingFailed(URLError(.badServerResponse))
            .errorDescription?.isEmpty == false)
    }
}
