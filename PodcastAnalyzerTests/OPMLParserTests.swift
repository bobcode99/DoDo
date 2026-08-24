//
//  OPMLParserTests.swift
//  PodcastAnalyzerTests
//
//  OPML is how a whole library arrives from another app and how it leaves this
//  one. Both directions are unattended: nobody proofreads 200 feed URLs. A
//  parser that accepts a folder `<outline>` as a feed imports garbage shows, and
//  an exporter that doesn't escape `&` writes a file no reader will parse —
//  which the user only discovers on the far side of a migration.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("OPML import and export")
struct OPMLParserTests {

    private func data(_ xml: String) -> Data { Data(xml.utf8) }

    private func podcast(title: String, rss: String) -> PodcastInfo {
        PodcastInfo(
            title: title,
            description: "Description",
            episodes: [],
            rssUrl: rss,
            imageURL: "https://example.com/art.jpg",
            language: "en"
        )
    }

    // MARK: - Import

    @Test("Every rss outline in the document yields its feed URL, in order")
    func parsesFeedURLs() {
        let urls = OPMLParser.parse(data: data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>Subscriptions</title></head>
          <body>
            <outline type="rss" text="First" xmlUrl="https://example.com/first.xml"/>
            <outline type="rss" text="Second" xmlUrl="https://example.com/second.xml"/>
          </body>
        </opml>
        """))

        #expect(urls == ["https://example.com/first.xml", "https://example.com/second.xml"])
    }

    @Test("Feeds nested inside folder outlines are still found")
    func parsesNestedOutlines() {
        let urls = OPMLParser.parse(data: data("""
        <opml version="2.0"><body>
          <outline text="Tech">
            <outline type="rss" text="Nested" xmlUrl="https://example.com/nested.xml"/>
          </outline>
        </body></opml>
        """))

        #expect(urls == ["https://example.com/nested.xml"])
    }

    @Test("A folder outline is not itself imported as a feed")
    func ignoresFolderOutlines() {
        let urls = OPMLParser.parse(data: data("""
        <opml version="2.0"><body>
          <outline text="Just A Folder"/>
          <outline type="link" text="A Link" url="https://example.com"/>
        </body></opml>
        """))

        #expect(urls.isEmpty)
    }

    @Test("An rss outline missing or emptying its xmlUrl is skipped")
    func skipsOutlinesWithoutURL() {
        let urls = OPMLParser.parse(data: data("""
        <opml version="2.0"><body>
          <outline type="rss" text="No URL"/>
          <outline type="rss" text="Blank URL" xmlUrl=""/>
          <outline type="rss" text="Good" xmlUrl="https://example.com/good.xml"/>
        </body></opml>
        """))

        #expect(urls == ["https://example.com/good.xml"])
    }

    @Test("The type attribute is matched case-insensitively, as exporters vary")
    func matchesTypeCaseInsensitively() {
        let urls = OPMLParser.parse(data: data("""
        <opml version="2.0"><body>
          <outline type="RSS" text="Shouty" xmlUrl="https://example.com/shouty.xml"/>
        </body></opml>
        """))

        #expect(urls == ["https://example.com/shouty.xml"])
    }

    @Test("Malformed or empty input imports nothing instead of throwing")
    func handlesMalformedInput() {
        #expect(OPMLParser.parse(data: Data()).isEmpty)
        #expect(OPMLParser.parse(data: data("not xml at all")).isEmpty)
        #expect(OPMLParser.parse(data: data("<opml><body><outline type=\"rss\"")).isEmpty)
    }

    @Test("A document with no subscriptions imports nothing")
    func handlesEmptyBody() {
        #expect(OPMLParser.parse(data: data("<opml version=\"2.0\"><body></body></opml>")).isEmpty)
    }

    // MARK: - Export

    @Test("Export writes one outline per subscription inside a valid OPML shell")
    func exportsSubscriptions() {
        let opml = OPMLParser.export(podcasts: [
            podcast(title: "First Show", rss: "https://example.com/first.xml"),
            podcast(title: "Second Show", rss: "https://example.com/second.xml"),
        ])

        #expect(opml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(opml.contains("<opml version=\"2.0\">"))
        #expect(opml.contains(#"text="First Show""#))
        #expect(opml.contains(#"xmlUrl="https://example.com/second.xml""#))
        #expect(opml.hasSuffix("</opml>"))
    }

    @Test("A subscription with no feed URL is left out of the export")
    func exportSkipsFeedlessPodcasts() {
        let opml = OPMLParser.export(podcasts: [
            podcast(title: "Ghost", rss: ""),
            podcast(title: "Real", rss: "https://example.com/real.xml"),
        ])

        #expect(opml.contains("Ghost") == false)
        #expect(opml.contains("Real"))
    }

    @Test("Titles and URLs carrying XML metacharacters are escaped")
    func escapesMetacharacters() {
        let opml = OPMLParser.export(podcasts: [
            podcast(title: #"Tom & Jerry <"Best Of">"#,
                    rss: "https://example.com/feed?a=1&b=2")
        ])

        #expect(opml.contains("Tom &amp; Jerry &lt;&quot;Best Of&quot;&gt;"))
        #expect(opml.contains("a=1&amp;b=2"))
        // No raw metacharacter survives inside an attribute value.
        #expect(opml.contains("Tom & Jerry") == false)
    }

    @Test("Exporting nothing still produces a document a reader can open")
    func exportsEmptyLibrary() {
        let opml = OPMLParser.export(podcasts: [])
        #expect(opml.contains("<body>"))
        #expect(OPMLParser.parse(data: data(opml)).isEmpty)
    }

    // MARK: - Round trip

    @Test("Exporting then re-importing recovers exactly the feed URLs, escapes included")
    func roundTrips() {
        let podcasts = [
            podcast(title: "Plain", rss: "https://example.com/plain.xml"),
            podcast(title: "Tricky & <Odd>", rss: "https://example.com/feed?a=1&b=2"),
        ]

        let reimported = OPMLParser.parse(data: data(OPMLParser.export(podcasts: podcasts)))
        #expect(reimported == podcasts.map(\.rssUrl))
    }
}
