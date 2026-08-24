//
//  DiscoveryCacheStoreTests.swift
//  PodcastAnalyzerTests
//
//  This cache is what Home paints on a cold launch, before the network answers
//  — and the whole tab when there is no network at all. It is read
//  *synchronously on the main thread* on the strength of the payload being tiny,
//  which is why the 25-row cap is a correctness property here and not a
//  nice-to-have. A corrupt or half-written file must read as "no cache", never
//  as a crash on launch.
//
//  Each test uses a unique region code so it writes its own file and cleans up
//  after itself, leaving the real regions untouched.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Discovery cache")
struct DiscoveryCacheStoreTests {

    /// A region code no storefront uses, unique per test.
    private func scratchRegion() -> String {
        "zz" + UUID().uuidString.prefix(6).lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Mirrors the store's own path derivation so tests can clean up and can
    /// plant a deliberately corrupt file.
    private func cacheFile(region: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let safe = region.lowercased().filter { $0.isLetter || $0.isNumber }
        return caches
            .appendingPathComponent("DiscoveryCache", isDirectory: true)
            .appendingPathComponent("top-\(safe).json")
    }

    private func remove(region: String) {
        try? FileManager.default.removeItem(at: cacheFile(region: region))
    }

    private func podcast(_ id: String) -> AppleRSSPodcast {
        AppleRSSPodcast(
            id: id,
            artistName: "Artist \(id)",
            name: "Show \(id)",
            artworkUrl100: "https://example.com/\(id).jpg",
            url: "https://podcasts.apple.com/\(id)",
            genres: nil,
            contentAdvisoryRating: nil,
            releaseDate: nil,
            kind: "podcast"
        )
    }

    // MARK: - Round trip

    @Test("A saved list reads back with its shows and a fetch time")
    func savesAndLoads() throws {
        let region = scratchRegion()
        defer { remove(region: region) }

        let before = Date()
        DiscoveryCacheStore.saveTopPodcasts([podcast("1"), podcast("2")], region: region)

        let cached = try #require(DiscoveryCacheStore.loadTopPodcasts(region: region))
        #expect(cached.podcasts.map(\.id) == ["1", "2"])
        #expect(cached.podcasts[0].name == "Show 1")
        #expect(cached.fetchedAt >= before)
    }

    @Test("Saving again replaces the previous list rather than appending to it")
    func saveOverwrites() throws {
        let region = scratchRegion()
        defer { remove(region: region) }

        DiscoveryCacheStore.saveTopPodcasts([podcast("old")], region: region)
        DiscoveryCacheStore.saveTopPodcasts([podcast("new")], region: region)

        #expect(try #require(DiscoveryCacheStore.loadTopPodcasts(region: region))
            .podcasts.map(\.id) == ["new"])
    }

    @Test("Only the first 25 rows are stored, since that is all Home renders")
    func capsStoredRows() throws {
        let region = scratchRegion()
        defer { remove(region: region) }

        DiscoveryCacheStore.saveTopPodcasts((1...200).map { podcast("\($0)") }, region: region)

        let cached = try #require(DiscoveryCacheStore.loadTopPodcasts(region: region))
        #expect(cached.podcasts.count == 25)
        // The cap takes from the top of the chart, not a random slice.
        #expect(cached.podcasts.first?.id == "1")
        #expect(cached.podcasts.last?.id == "25")
    }

    @Test("Region codes are matched case-insensitively")
    func regionIsCaseInsensitive() throws {
        let region = scratchRegion()
        defer { remove(region: region) }

        DiscoveryCacheStore.saveTopPodcasts([podcast("1")], region: region.uppercased())
        #expect(DiscoveryCacheStore.loadTopPodcasts(region: region) != nil)
    }

    // MARK: - Nothing to show

    @Test("A region that was never cached reads as empty, not as a failure")
    func missingRegion() {
        #expect(DiscoveryCacheStore.loadTopPodcasts(region: scratchRegion()) == nil)
    }

    @Test("An empty result is not written, so a bad fetch can't erase a good cache")
    func emptyListIsNotSaved() throws {
        let region = scratchRegion()
        defer { remove(region: region) }

        DiscoveryCacheStore.saveTopPodcasts([podcast("1")], region: region)
        DiscoveryCacheStore.saveTopPodcasts([], region: region)

        // The good list is still there.
        #expect(try #require(DiscoveryCacheStore.loadTopPodcasts(region: region))
            .podcasts.map(\.id) == ["1"])
    }

    @Test("A corrupt or truncated cache file reads as no cache instead of crashing the launch")
    func corruptFileIsIgnored() throws {
        let region = scratchRegion()
        defer { remove(region: region) }

        // Seed the directory, then damage the file the way a killed write would.
        DiscoveryCacheStore.saveTopPodcasts([podcast("1")], region: region)
        try Data(#"{"podcasts":[{"id":"#.utf8).write(to: cacheFile(region: region))

        #expect(DiscoveryCacheStore.loadTopPodcasts(region: region) == nil)
    }

    @Test("A file holding a valid but empty list reads as no cache")
    func emptyStoredListReadsAsNothing() throws {
        let region = scratchRegion()
        defer { remove(region: region) }

        DiscoveryCacheStore.saveTopPodcasts([podcast("1")], region: region)
        let payload = #"{"podcasts":[],"fetchedAt":0}"#
        try Data(payload.utf8).write(to: cacheFile(region: region))

        #expect(DiscoveryCacheStore.loadTopPodcasts(region: region) == nil)
    }

    @Test("A show with no artwork still round-trips, and reads back as an empty URL")
    func handlesMissingArtwork() throws {
        let region = scratchRegion()
        defer { remove(region: region) }

        let artless = AppleRSSPodcast(
            id: "1", artistName: "Artist", name: "Show", artworkUrl100: nil,
            url: "https://podcasts.apple.com/1", genres: nil,
            contentAdvisoryRating: nil, releaseDate: nil, kind: nil)

        DiscoveryCacheStore.saveTopPodcasts([artless], region: region)

        let cached = try #require(DiscoveryCacheStore.loadTopPodcasts(region: region))
        #expect(cached.podcasts[0].artworkUrl100 == nil)
        #expect(cached.podcasts[0].safeArtworkUrl.isEmpty)
    }
}
