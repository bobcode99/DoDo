//
//  ExpandedPlayerViewModelStateTests.swift
//  PodcastAnalyzerTests
//
//  What the expanded player knows about the episode it opens on: the star flag
//  and the show behind it. The view model is built before the model context
//  exists, so these have to arrive with the context. Nested in the serialized
//  player suite: it sets `EnhancedAudioManager.shared.currentEpisode`.
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

extension PlayerInteractionFlowTests {

@MainActor
@Suite("Expanded player stored state")
struct ExpandedPlayerStoredState {

    private static var retainedStores: [ModelContainer] = []

    private func episode() -> PlaybackEpisode {
        PlaybackEpisode(
            id: EpisodeKeyUtils.makeKey(podcastTitle: "Daily Tech", episodeTitle: "Listening"),
            title: "Listening",
            podcastTitle: "Daily Tech",
            audioURL: "https://example.com/listening.mp3",
            imageURL: nil,
            episodeDescription: nil,
            pubDate: nil,
            duration: 1800,
            guid: nil
        )
    }

    /// Runs `body` with `episode` as the current episode and a store holding
    /// its download model (starred) and its show (in `language`).
    private func withStoredEpisode(
        language: String,
        _ body: (ModelContext) -> Void
    ) throws {
        let schema = Schema([PodcastInfoModel.self, EpisodeDownloadModel.self, QueueItemModel.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        Self.retainedStores.append(container)

        let ep = episode()
        container.mainContext.insert(
            EpisodeDownloadModel(
                episodeTitle: ep.title, podcastTitle: ep.podcastTitle, audioURL: ep.audioURL,
                isStarred: true))
        container.mainContext.insert(
            PodcastInfoModel(
                podcastInfo: PodcastInfo(
                    title: ep.podcastTitle, description: nil, episodes: [],
                    rssUrl: "https://example.com/feed.xml", imageURL: "", language: language),
                lastUpdated: .now))

        let manager = EnhancedAudioManager.shared
        let previous = manager.currentEpisode
        manager.restoreLastEpisode()  // spend the one-shot restore so it can't overwrite ours
        manager.currentEpisode = ep
        defer { manager.currentEpisode = previous }

        body(container.mainContext)
    }

    @Test("A starred episode opens the player as starred")
    func loadsStarFlagWhenContextArrives() throws {
        try withStoredEpisode(language: "en") { context in
            // ExpandedPlayerView creates the view model first and hands over the
            // context from onAppear.
            let viewModel = ExpandedPlayerViewModel()
            viewModel.setModelContext(context)

            #expect(viewModel.isStarred)
        }
    }

    @Test("The show behind the episode is known as soon as the player opens")
    func loadsPodcastModelWhenContextArrives() throws {
        try withStoredEpisode(language: "en") { context in
            let viewModel = ExpandedPlayerViewModel()
            viewModel.setModelContext(context)

            #expect(viewModel.podcastModel?.title == "Daily Tech")
        }
    }
}

}
