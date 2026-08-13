//
//  DiscoveryToSubscribeFlowTests.swift
//  PodcastAnalyzerTests
//
//  Stage 1 of the user journey: search a show → pick a result → subscribe.
//
//  The network legs (iTunes search, RSS fetch) are not exercised — they are
//  thin URLSession wrappers around the decoders and parsers tested here.
//  What IS covered is everything that decides what the user ends up with:
//  which payloads decode, which results are subscribable, and the upsert
//  rules that keep a second subscribe from creating a duplicate show.
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Journey: search → subscribe")
struct DiscoveryToSubscribeFlowTests {

    // MARK: - Search results

    @Test("A search payload decodes into results the user can subscribe to")
    func searchResultsDecode() throws {
        let json = Data("""
        {
          "resultCount": 2,
          "results": [
            {
              "collectionId": 1234,
              "collectionName": "Daily Tech",
              "artistName": "Tech Media",
              "artworkUrl100": "https://example.com/art100.jpg",
              "feedUrl": "https://example.com/feed.xml",
              "contentAdvisoryRating": "Explicit",
              "genres": ["Technology", "News"]
            },
            {
              "collectionId": 5678,
              "collectionName": "No Feed Show",
              "artistName": "Someone"
            }
          ]
        }
        """.utf8)

        let response = try JSONDecoder().decode(SearchResponse.self, from: json)

        #expect(response.resultCount == 2)
        #expect(response.results.count == 2)

        let first = try #require(response.results.first)
        #expect(first.collectionId == 1234)
        #expect(first.collectionName == "Daily Tech")
        #expect(first.feedUrl == "https://example.com/feed.xml")
        #expect(first.genres == ["Technology", "News"])

        // Every optional really is optional: a result missing artwork and feed
        // URL must still decode, because the whole list fails to render if one
        // sparse row throws.
        let second = response.results[1]
        #expect(second.artworkUrl100 == nil)
        #expect(second.feedUrl == nil, "a show with no feed URL cannot be subscribed to")
    }

    @Test("An episode-search payload decodes with the fields the episode rows read")
    func episodeResultsDecode() throws {
        let json = Data("""
        {
          "resultCount": 1,
          "results": [
            {
              "wrapperType": "podcastEpisode",
              "trackName": "Episode 1",
              "description": "First one",
              "releaseDate": "2026-01-02T03:04:05Z",
              "trackTimeMillis": 1800000,
              "episodeUrl": "https://example.com/1.mp3",
              "artworkUrl600": "https://example.com/600.jpg",
              "collectionName": "Daily Tech",
              "genres": [{ "name": "Technology", "id": "1318" }]
            }
          ]
        }
        """.utf8)

        let response = try JSONDecoder().decode(EpisodeSearchResponse.self, from: json)
        let episode = try #require(response.results.first)

        #expect(episode.trackName == "Episode 1")
        #expect(episode.episodeUrl == "https://example.com/1.mp3")
        #expect(episode.trackTimeMillis == 1_800_000)
        #expect(episode.genres?.first?.name == "Technology")
        // trackId is absent for RSS-sourced episodes — must not be required.
        #expect(episode.trackId == nil)
    }

    @Test("An empty or whitespace query clears results instead of firing a search")
    func blankQueryDoesNotSearch() throws {
        let viewModel = PodcastSearchViewModel()
        let json = Data("""
        {"resultCount":1,"results":[{"collectionId":1,"collectionName":"X","artistName":"Y"}]}
        """.utf8)
        viewModel.podcasts = try JSONDecoder().decode(SearchResponse.self, from: json).results
        #expect(!viewModel.podcasts.isEmpty)

        viewModel.searchText = "   "
        viewModel.performSearch()

        #expect(viewModel.podcasts.isEmpty, "stale results must not survive a cleared query")
        #expect(!viewModel.isLoading, "a skipped search must not leave the spinner on")
    }

    // MARK: - Subscribing

    /// One container for the whole suite: a fresh in-memory container per test
    /// has been observed to destabilize the SwiftData runtime on this OS build
    /// (see the note in SubscriptionSyncCoordinatorTests).
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PodcastInfoModel.self, SubscribedPodcastModel.self, EpisodeDownloadModel.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeInfo(
        title: String,
        rss: String,
        episodes: [PodcastEpisodeInfo] = []
    ) -> PodcastInfo {
        PodcastInfo(
            title: title,
            description: "desc",
            episodes: episodes,
            rssUrl: rss,
            imageURL: "https://example.com/art.jpg",
            language: "en"
        )
    }

    @Test("Subscribing stores the show, its episodes, and the queryable mirrors")
    func subscribeStoresShow() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let episodes = [
            PodcastEpisodeInfo(
                title: "Episode 1",
                pubDate: Date(timeIntervalSince1970: 1_000_000),
                audioURL: "https://example.com/1.mp3",
                duration: 1800
            ),
            PodcastEpisodeInfo(
                title: "Episode 2",
                pubDate: Date(timeIntervalSince1970: 2_000_000),
                audioURL: "https://example.com/2.mp3",
                duration: 2400
            ),
        ]
        let model = PodcastInfoModel(
            podcastInfo: makeInfo(title: "Daily Tech", rss: "https://example.com/feed.xml", episodes: episodes),
            lastUpdated: Date(),
            isSubscribed: true
        )
        context.insert(model)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<PodcastInfoModel>()).first)
        #expect(stored.isSubscribed)
        #expect(stored.title == "Daily Tech", "title mirror drives the #Predicate lookups")
        #expect(stored.rssUrl == "https://example.com/feed.xml")
        #expect(stored.episodeCount == 2)
        #expect(stored.latestEpisodeDate == Date(timeIntervalSince1970: 2_000_000))
        #expect(stored.podcastInfo.episodes.count == 2)
    }

    @Test("Subscribing to the same feed twice updates the existing show, never duplicates it")
    func resubscribeUpsertsByFeedURL() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let feed = "https://example.com/dup-feed.xml"

        let first = PodcastInfoModel(
            podcastInfo: makeInfo(title: "Old Name", rss: feed),
            lastUpdated: Date(timeIntervalSince1970: 0),
            isSubscribed: false
        )
        context.insert(first)
        try context.save()

        // Second subscribe: the view model looks up by RSS URL, flips the flag
        // and refreshes the payload rather than inserting.
        let existing = try #require(try context.fetch(FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.rssUrl == feed }
        )).first)
        existing.setSubscribed(true)
        existing.applyPodcastInfo(makeInfo(
            title: "New Name",
            rss: feed,
            episodes: [PodcastEpisodeInfo(title: "Episode 1", audioURL: "https://example.com/1.mp3")]
        ))
        try context.save()

        let all = try context.fetch(FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.rssUrl == feed }
        ))
        #expect(all.count == 1, "resubscribing must not create a second row for the same feed")
        #expect(all.first?.isSubscribed == true)
        #expect(all.first?.title == "New Name", "the refreshed feed title must reach the mirror")
        #expect(all.first?.episodeCount == 1)
    }

    @Test("Unsubscribing keeps the cached show but clears the subscribed flag")
    func unsubscribeKeepsCachedShow() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let model = PodcastInfoModel(
            podcastInfo: makeInfo(title: "Leaving Soon", rss: "https://example.com/bye.xml"),
            lastUpdated: Date(),
            isSubscribed: true
        )
        context.insert(model)
        try context.save()

        model.setSubscribed(false)
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.rssUrl == "https://example.com/bye.xml" }
        )).first)
        #expect(!stored.isSubscribed)
        #expect(stored.title == "Leaving Soon", "the row survives so browsing it stays instant")

        // The funnel is idempotent — a redundant unsubscribe is a no-op.
        stored.setSubscribed(false)
        #expect(!stored.isSubscribed)
    }

    @Test("The subscribed-shows query returns only subscribed rows")
    func subscribedQuerySeparatesBrowsedShows() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let subscribed = PodcastInfoModel(
            podcastInfo: makeInfo(title: "Followed", rss: "https://example.com/followed.xml"),
            lastUpdated: Date(),
            isSubscribed: true
        )
        let browsed = PodcastInfoModel(
            podcastInfo: makeInfo(title: "Just Browsed", rss: "https://example.com/browsed.xml"),
            lastUpdated: Date(),
            isSubscribed: false
        )
        context.insert(subscribed)
        context.insert(browsed)
        try context.save()

        let library = try context.fetch(FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.isSubscribed }
        ))
        #expect(library.map(\.title) == ["Followed"])
    }
}
