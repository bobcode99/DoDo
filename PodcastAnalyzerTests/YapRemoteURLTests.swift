//
//  YapRemoteURLTests.swift
//  PodcastAnalyzerTests
//
//  `?timestamp` is a per-request tracking value that podcast CDNs hang off the
//  enclosure URL. Sending it to the yap server makes every submission look like
//  a different asset, and hosts that validate it reject a stale one.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@Suite("Yap remote URL sanitising")
struct YapRemoteURLTests {

    private func strip(_ raw: String) -> String {
        YapTranscriptService.strippingTimestamp(raw)
    }

    @Test("drops a lone timestamp param, and the ? with it")
    func dropsLoneTimestamp() {
        #expect(
            strip("https://cdn.example/ep1.mp3?timestamp=1754630000")
                == "https://cdn.example/ep1.mp3"
        )
    }

    @Test("keeps the other params the CDN needs")
    func keepsSiblingParams() {
        let result = strip("https://cdn.example/ep1.mp3?token=abc&timestamp=1754630000&e=42")
        #expect(result == "https://cdn.example/ep1.mp3?token=abc&e=42")
    }

    @Test("leaves a URL without a timestamp untouched", arguments: [
        "https://cdn.example/ep1.mp3",
        "https://cdn.example/ep1.mp3?token=abc",
        "https://cdn.example/path%20with%20space/ep1.mp3?token=a%2Bb",
    ])
    func passesThroughUnrelated(_ url: String) {
        #expect(strip(url) == url)
    }

    @Test("preserves percent-encoding in the params it keeps")
    func preservesEncoding() {
        let result = strip("https://cdn.example/ep.mp3?sig=a%2Bb%2Fc&timestamp=1")
        #expect(result == "https://cdn.example/ep.mp3?sig=a%2Bb%2Fc")
    }

    @Test("only strips an exact `timestamp` key, not lookalikes")
    func doesNotStripLookalikes() {
        let raw = "https://cdn.example/ep.mp3?timestamps=1&x_timestamp=2"
        #expect(strip(raw) == raw)
    }

    @Test("a non-URL string is returned unchanged rather than dropped")
    func malformedInputSurvives() {
        // Better to submit something the server can reject with a clear error
        // than to silently hand it an empty URL.
        #expect(strip("") == "")
        #expect(strip("not a url") == "not a url")
    }
}
