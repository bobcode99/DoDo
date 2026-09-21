//
//  AppleArtworkURLTests.swift
//  PodcastAnalyzerTests
//
//  Every artwork request goes through one canonical URL so the disk cache holds
//  a single entry per cover. If two screens asked for different sizes, art seen
//  online on one screen was a cache miss (blank) on the other once offline.
//

import Testing

@testable import PodcastAnalyzer

@Suite("Apple artwork URL")
struct AppleArtworkURLTests {

    @Test("Any Apple size rewrites to the one canonical size", arguments: [
        "https://is1-ssl.mzstatic.com/image/thumb/Podcasts/a/b/c/100x100bb.jpg",
        "https://is1-ssl.mzstatic.com/image/thumb/Podcasts/a/b/c/3000x3000bb.png",
        "https://is1-ssl.mzstatic.com/image/thumb/Podcasts/a/b/c/60x60bb.webp",
    ])
    func canonicalizesAppleSizes(_ url: String) {
        #expect(AppleArtworkURL.canonical(url).contains("/600x600bb."))
    }

    @Test("Sizes seen by different screens collapse to the same URL")
    func differentSizesShareOneURL() {
        let base = "https://is1-ssl.mzstatic.com/image/thumb/Podcasts/a/b/c/"
        #expect(AppleArtworkURL.canonical(base + "168x168bb.jpg") == AppleArtworkURL.canonical(base + "840x840bb.jpg"))
    }

    @Test("Non-Apple artwork URLs pass through untouched")
    func leavesOtherURLsAlone() {
        let url = "https://megaphone.imgix.net/podcasts/art.jpg?ixlib=rails-4.3.1&max-w=3000"
        #expect(AppleArtworkURL.canonical(url) == url)
    }
}
