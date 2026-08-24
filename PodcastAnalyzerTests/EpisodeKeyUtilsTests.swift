//
//  EpisodeKeyUtilsTests.swift
//  PodcastAnalyzerTests
//
//  `"\(podcastTitle)\u{1F}\(episodeTitle)"` is the upsert key for
//  `EpisodeDownloadModel` and the identity used by download state, queue
//  membership, and progress. Splitting it wrongly doesn't throw — it produces a
//  *different* episode, so playback progress lands on the wrong row and the
//  download that finished belongs to nobody.
//
//  The delimiter is a Unit Separator precisely because titles contain every
//  printable character; the old `|` format is still readable for rows written
//  before the change.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Episode composite keys")
struct EpisodeKeyUtilsTests {

    @Test("A key is the two titles joined by the Unit Separator")
    func makesKey() {
        let key = EpisodeKeyUtils.makeKey(podcastTitle: "The Show", episodeTitle: "Episode 1")
        #expect(key == "The Show\u{1F}Episode 1")
    }

    @Test("A key round-trips back to the titles it was built from")
    func roundTrips() throws {
        let parsed = try #require(EpisodeKeyUtils.parseKey(
            EpisodeKeyUtils.makeKey(podcastTitle: "The Show", episodeTitle: "Episode 1")))

        #expect(parsed.podcastTitle == "The Show")
        #expect(parsed.episodeTitle == "Episode 1")
    }

    @Test("A pipe in either title is data, not a delimiter")
    func pipesInTitlesAreData() throws {
        let parsed = try #require(EpisodeKeyUtils.parseKey(
            EpisodeKeyUtils.makeKey(podcastTitle: "Tech | Weekly",
                                    episodeTitle: "Part 2 | Finale")))

        #expect(parsed.podcastTitle == "Tech | Weekly")
        #expect(parsed.episodeTitle == "Part 2 | Finale")
    }

    @Test("Titles carrying punctuation, emoji and CJK survive the round trip intact")
    func roundTripsAwkwardTitles() throws {
        let podcast = "科技 & 生活 🎧"
        let episode = "#42: \"The Best One\" — part 1/2"

        let parsed = try #require(EpisodeKeyUtils.parseKey(
            EpisodeKeyUtils.makeKey(podcastTitle: podcast, episodeTitle: episode)))

        #expect(parsed.podcastTitle == podcast)
        #expect(parsed.episodeTitle == episode)
    }

    @Test("Empty titles still produce a parseable key")
    func handlesEmptyTitles() throws {
        let parsed = try #require(EpisodeKeyUtils.parseKey(
            EpisodeKeyUtils.makeKey(podcastTitle: "", episodeTitle: "")))

        #expect(parsed.podcastTitle.isEmpty)
        #expect(parsed.episodeTitle.isEmpty)
    }

    @Test("Keys written in the old pipe format are still readable")
    func readsLegacyPipeKeys() throws {
        let parsed = try #require(EpisodeKeyUtils.parseKey("The Show|Episode 1"))
        #expect(parsed.podcastTitle == "The Show")
        #expect(parsed.episodeTitle == "Episode 1")
    }

    @Test("A legacy key splits at the last pipe, so a piped podcast title survives")
    func legacySplitsAtLastPipe() throws {
        let parsed = try #require(EpisodeKeyUtils.parseKey("Tech | Weekly|Episode 1"))
        #expect(parsed.podcastTitle == "Tech | Weekly")
        #expect(parsed.episodeTitle == "Episode 1")
    }

    @Test("The Unit Separator wins over a pipe when a key contains both")
    func separatorBeatsPipe() throws {
        let parsed = try #require(EpisodeKeyUtils.parseKey("Tech | Weekly\u{1F}Part 1 | 2"))
        #expect(parsed.podcastTitle == "Tech | Weekly")
        #expect(parsed.episodeTitle == "Part 1 | 2")
    }

    @Test("A string with no delimiter at all is not a key")
    func rejectsNonKeys() {
        #expect(EpisodeKeyUtils.parseKey("just a title") == nil)
        #expect(EpisodeKeyUtils.parseKey("") == nil)
    }

    @Test("Keys differ whenever either title differs")
    func keysAreDistinct() {
        let a = EpisodeKeyUtils.makeKey(podcastTitle: "Show", episodeTitle: "One")
        let b = EpisodeKeyUtils.makeKey(podcastTitle: "Show", episodeTitle: "Two")
        let c = EpisodeKeyUtils.makeKey(podcastTitle: "Other", episodeTitle: "One")

        #expect(a != b)
        #expect(a != c)
    }

    @Test("The delimiter can't be spoofed by concatenating the titles differently")
    func noAmbiguityAcrossTheBoundary() {
        // "AB" + "C" and "A" + "BC" must not collide.
        #expect(EpisodeKeyUtils.makeKey(podcastTitle: "AB", episodeTitle: "C")
                != EpisodeKeyUtils.makeKey(podcastTitle: "A", episodeTitle: "BC"))
    }
}
