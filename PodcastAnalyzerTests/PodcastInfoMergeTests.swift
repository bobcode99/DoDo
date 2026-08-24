//
//  PodcastInfoMergeTests.swift
//  PodcastAnalyzerTests
//
//  Feeds trim their backlog. When a show drops everything older than 50
//  episodes, a naive refresh replaces the stored list and the episode the user
//  downloaded last month disappears from the app while its audio file stays on
//  disk. `merging(updatedFrom:preservedKeys:)` is the rule that keeps a touched
//  episode visible; everything untouched is allowed to fall off.
//
//  The preserved-key check is built from the *updated* title, which matters the
//  one time it is hard to notice: the refresh where the show renamed itself.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Feed refresh merge")
struct PodcastInfoMergeTests {

    private func episode(
        _ title: String, guid: String? = nil, audioURL: String? = nil
    ) -> PodcastEpisodeInfo {
        PodcastEpisodeInfo(
            title: title,
            pubDate: Date(timeIntervalSince1970: 1_700_000_000),
            audioURL: audioURL ?? "https://example.com/\(title).mp3",
            duration: 3600,
            guid: guid
        )
    }

    private func podcast(
        title: String = "The Show",
        episodes: [PodcastEpisodeInfo],
        imageURL: String = "https://example.com/art.jpg",
        language: String = "en",
        author: String? = "Author",
        people: [PodcastPerson] = []
    ) -> PodcastInfo {
        PodcastInfo(
            title: title,
            description: "A show.",
            episodes: episodes,
            rssUrl: "https://example.com/feed.xml",
            imageURL: imageURL,
            language: language,
            author: author,
            people: people
        )
    }

    private func key(_ podcast: String, _ episode: String) -> String {
        EpisodeKeyUtils.makeKey(podcastTitle: podcast, episodeTitle: episode)
    }

    // MARK: - Preservation

    @Test("An episode the user downloaded survives the feed dropping it")
    func preservesTouchedEpisode() {
        let stored = podcast(episodes: [episode("Old"), episode("Recent")])
        let refreshed = podcast(episodes: [episode("Recent"), episode("New")])

        let merged = stored.merging(
            updatedFrom: refreshed, preservedKeys: [key("The Show", "Old")])

        #expect(merged.episodes.map(\.title) == ["Recent", "New", "Old"])
    }

    @Test("An episode nobody touched is allowed to fall off the backlog")
    func dropsUntouchedEpisode() {
        let stored = podcast(episodes: [episode("Old"), episode("Recent")])
        let refreshed = podcast(episodes: [episode("Recent")])

        let merged = stored.merging(updatedFrom: refreshed, preservedKeys: [])
        #expect(merged.episodes.map(\.title) == ["Recent"])
    }

    @Test("Preserved episodes go after the current feed, not interleaved into it")
    func preservedEpisodesGoLast() {
        let stored = podcast(episodes: [episode("A"), episode("B"), episode("C")])
        let refreshed = podcast(episodes: [episode("C")])

        let merged = stored.merging(
            updatedFrom: refreshed,
            preservedKeys: [key("The Show", "A"), key("The Show", "B")])

        #expect(merged.episodes.map(\.title) == ["C", "A", "B"])
    }

    @Test("An episode still in the feed is listed once, not twice")
    func noDuplicatesForEpisodesStillPresent() {
        let stored = podcast(episodes: [episode("Recent")])
        let refreshed = podcast(episodes: [episode("Recent")])

        let merged = stored.merging(
            updatedFrom: refreshed, preservedKeys: [key("The Show", "Recent")])

        #expect(merged.episodes.count == 1)
    }

    @Test("Identity is the GUID, so a re-hosted episode isn't resurrected as a duplicate")
    func identityPrefersGUID() {
        // Same episode, new CDN: the audio URL changed but the GUID did not.
        let stored = podcast(episodes: [
            episode("Episode 1", guid: "guid-1", audioURL: "https://old.example.com/1.mp3")
        ])
        let refreshed = podcast(episodes: [
            episode("Episode 1", guid: "guid-1", audioURL: "https://new.example.com/1.mp3")
        ])

        let merged = stored.merging(
            updatedFrom: refreshed, preservedKeys: [key("The Show", "Episode 1")])

        #expect(merged.episodes.map(\.audioURL) == ["https://new.example.com/1.mp3"])
    }

    @Test("With no GUID, the audio URL identifies the episode")
    func identityFallsBackToAudioURL() {
        let stored = podcast(episodes: [episode("Episode 1", audioURL: "https://example.com/1.mp3")])
        let refreshed = podcast(episodes: [
            // Same file, retitled by the publisher.
            episode("Episode 1 (Remastered)", audioURL: "https://example.com/1.mp3")
        ])

        let merged = stored.merging(
            updatedFrom: refreshed, preservedKeys: [key("The Show", "Episode 1")])

        #expect(merged.episodes.map(\.title) == ["Episode 1 (Remastered)"])
    }

    @Test("A show that renames itself still matches preserved keys built from the new name")
    func preservedKeysUseTheUpdatedTitle() {
        let stored = podcast(title: "Old Name", episodes: [episode("Kept"), episode("Current")])
        let refreshed = podcast(title: "New Name", episodes: [episode("Current")])

        let byNewName = stored.merging(
            updatedFrom: refreshed, preservedKeys: [key("New Name", "Kept")])
        #expect(byNewName.episodes.map(\.title) == ["Current", "Kept"])

        let byOldName = stored.merging(
            updatedFrom: refreshed, preservedKeys: [key("Old Name", "Kept")])
        #expect(byOldName.episodes.map(\.title) == ["Current"])
    }

    // MARK: - Metadata

    @Test("Show metadata comes from the refresh, so a new title or artwork takes effect")
    func metadataComesFromTheRefresh() {
        let stored = podcast(title: "Old Name", episodes: [],
                             imageURL: "https://example.com/old.jpg",
                             language: "en", author: "Old Author")
        let refreshed = podcast(title: "New Name", episodes: [],
                                imageURL: "https://example.com/new.jpg",
                                language: "zh-Hant", author: "New Author")

        let merged = stored.merging(updatedFrom: refreshed, preservedKeys: [])

        #expect(merged.title == "New Name")
        #expect(merged.imageURL == "https://example.com/new.jpg")
        #expect(merged.language == "zh-Hant")
        #expect(merged.author == "New Author")
        #expect(merged.rssUrl == refreshed.rssUrl)
        #expect(merged.id == refreshed.rssUrl)
    }

    @Test("The refreshed cast list replaces the stored one")
    func castComesFromTheRefresh() {
        let stored = podcast(episodes: [], people: [
            PodcastPerson(name: "Former Host", role: "host", group: nil)
        ])
        let refreshed = podcast(episodes: [], people: [
            PodcastPerson(name: "Current Host", role: "host", group: nil)
        ])

        let merged = stored.merging(updatedFrom: refreshed, preservedKeys: [])
        #expect(merged.people.map(\.name) == ["Current Host"])
    }

    // MARK: - Degenerate cases

    @Test("A feed that comes back empty keeps only what the user touched")
    func emptyRefresh() {
        let stored = podcast(episodes: [episode("Kept"), episode("Dropped")])
        let refreshed = podcast(episodes: [])

        let merged = stored.merging(
            updatedFrom: refreshed, preservedKeys: [key("The Show", "Kept")])

        #expect(merged.episodes.map(\.title) == ["Kept"])
    }

    @Test("Merging into an empty stored show just takes the feed")
    func emptyStored() {
        let stored = podcast(episodes: [])
        let refreshed = podcast(episodes: [episode("A"), episode("B")])

        let merged = stored.merging(updatedFrom: refreshed, preservedKeys: [])
        #expect(merged.episodes.map(\.title) == ["A", "B"])
    }

    @Test("A preserved key naming an episode nobody has doesn't invent one")
    func unknownPreservedKeyIsIgnored() {
        let stored = podcast(episodes: [episode("A")])
        let refreshed = podcast(episodes: [episode("A")])

        let merged = stored.merging(
            updatedFrom: refreshed, preservedKeys: [key("The Show", "Never Existed")])

        #expect(merged.episodes.map(\.title) == ["A"])
    }
}

@MainActor
@Suite("Episode metadata")
struct PodcastEpisodeInfoTests {

    @Test("An episode is identified by its audio URL")
    func identityIsTheAudioURL() {
        let episode = PodcastEpisodeInfo(title: "One", audioURL: "https://example.com/1.mp3")
        #expect(episode.id == "https://example.com/1.mp3")
    }

    @Test("Without audio, identity falls back to title and date so two episodes don't collide")
    func identityFallsBackToTitleAndDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = PodcastEpisodeInfo(title: "One", pubDate: date)
        let second = PodcastEpisodeInfo(title: "Two", pubDate: date)
        let undated = PodcastEpisodeInfo(title: "One")

        #expect(first.id != second.id)
        #expect(first.id.contains("One"))
        #expect(undated.id.contains("unknown"))
    }

    @Test("Duration is displayed at the coarsest useful precision")
    func formatsDuration() {
        #expect(PodcastEpisodeInfo(title: "x", duration: 3900).formattedDuration == "1h 5m")
        #expect(PodcastEpisodeInfo(title: "x", duration: 2880).formattedDuration == "48m")
        #expect(PodcastEpisodeInfo(title: "x", duration: 200).formattedDuration == "3m 20s")
        #expect(PodcastEpisodeInfo(title: "x", duration: 45).formattedDuration == "45s")
    }

    @Test("A missing or zero duration shows nothing rather than '0s'")
    func hidesUnknownDuration() {
        #expect(PodcastEpisodeInfo(title: "x", duration: nil).formattedDuration == nil)
        #expect(PodcastEpisodeInfo(title: "x", duration: 0).formattedDuration == nil)
    }

    @Test("An episode survives a JSON round trip with every field intact")
    func roundTripsThroughJSON() throws {
        let episode = PodcastEpisodeInfo(
            title: "Episode 1",
            podcastEpisodeDescription: "Notes & things",
            pubDate: Date(timeIntervalSince1970: 1_700_000_000),
            audioURL: "https://example.com/1.mp3",
            imageURL: "https://example.com/1.jpg",
            duration: 3600,
            guid: "guid-1",
            transcriptURL: "https://example.com/1.vtt",
            transcriptType: "text/vtt",
            chaptersURL: "https://example.com/1.json"
        )

        let decoded = try JSONDecoder().decode(
            PodcastEpisodeInfo.self, from: try JSONEncoder().encode(episode))

        #expect(decoded.title == episode.title)
        #expect(decoded.guid == "guid-1")
        #expect(decoded.transcriptType == "text/vtt")
        #expect(decoded.duration == 3600)
        #expect(decoded.id == episode.id)
    }

    @Test("A row written before transcripts existed still decodes")
    func decodesLegacyPayload() throws {
        let json = #"{"title":"Episode 1","audioURL":"https://example.com/1.mp3"}"#
        let decoded = try JSONDecoder().decode(PodcastEpisodeInfo.self, from: Data(json.utf8))

        #expect(decoded.title == "Episode 1")
        #expect(decoded.transcriptURL == nil)
        #expect(decoded.duration == nil)
    }
}
