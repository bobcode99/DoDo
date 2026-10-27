//
//  LibrarySearchFilterTests.swift
//  PodcastAnalyzerTests
//
//  Library-tab search: which subscribed episodes match a query, and which
//  show each match is credited to.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Library search filter")
struct LibrarySearchFilterTests {

    private func show(_ title: String, language: String = "en", episodes: [PodcastEpisodeInfo]) -> PodcastInfo {
        PodcastInfo(
            title: title,
            description: nil,
            episodes: episodes,
            rssUrl: "https://example.com/\(title).xml",
            imageURL: "https://example.com/\(title).jpg",
            language: language,
            author: nil,
            people: []
        )
    }

    @Test("Matches titles and descriptions, case-insensitively, across shows in order")
    func matchesTitleAndDescription() {
        let shows = [
            show("Alpha", episodes: [
                PodcastEpisodeInfo(title: "Fix Your Life"),
                PodcastEpisodeInfo(title: "Unrelated"),
            ]),
            show("Beta", language: "zh-TW", episodes: [
                PodcastEpisodeInfo(title: "Episode 9", podcastEpisodeDescription: "how to FIX everything"),
            ]),
        ]

        let results = LibrarySearchFilter.episodes(in: shows, matching: "fix")

        #expect(results.map(\.episode.title) == ["Fix Your Life", "Episode 9"])
        #expect(results.map(\.podcastTitle) == ["Alpha", "Beta"])
        let second = results[1]
        #expect(second.podcastImageURL == "https://example.com/Beta.jpg")
        #expect(second.podcastLanguage == "zh-TW", "the episode opens with its own show's language")
    }

    @Test("An empty query matches nothing instead of every episode")
    func emptyQueryMatchesNothing() {
        let shows = [show("Alpha", episodes: [PodcastEpisodeInfo(title: "Anything")])]
        #expect(LibrarySearchFilter.episodes(in: shows, matching: "").isEmpty)
    }

    @Test("No match returns no episodes")
    func noMatch() {
        let shows = [show("Alpha", episodes: [PodcastEpisodeInfo(title: "Anything")])]
        #expect(LibrarySearchFilter.episodes(in: shows, matching: "zzz").isEmpty)
    }
}
