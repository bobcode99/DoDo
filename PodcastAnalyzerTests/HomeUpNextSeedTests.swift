//
//  HomeUpNextSeedTests.swift
//  PodcastAnalyzerTests
//
//  Opening the app shows the episode being listened to in Up Next straight
//  away, not the "No unplayed episodes" empty state while the scored list
//  loads. Nested in the serialized player suite: it sets
//  `EnhancedAudioManager.shared.currentEpisode`.
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

extension PlayerInteractionFlowTests {

@MainActor
@Suite("Home Up Next first frame")
struct HomeUpNextSeed {

    /// A HomeViewModel can outlive its test: `loadAll()` holds it while awaiting
    /// a shared top-podcasts fetch, which cancellation doesn't interrupt. Its
    /// `currentEpisode` observer then reloads Up Next on the next change —
    /// against a freed store, crashing the host. Keeping stores alive makes that
    /// late reload harmless.
    /// ponytail: a few in-memory stores per run; give HomeViewModel a teardown
    /// that stops its observers if more suites need this.
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
    /// its download model, then waits for the full load so the store outlives it.
    private func withCurrentEpisode(
        completed: Bool,
        _ body: (HomeViewModel, PlaybackEpisode) throws -> Void
    ) async throws {
        let schema = Schema([PodcastInfoModel.self, EpisodeDownloadModel.self, QueueItemModel.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        Self.retainedStores.append(container)
        let ep = episode()
        let model = EpisodeDownloadModel(
            episodeTitle: ep.title, podcastTitle: ep.podcastTitle, audioURL: ep.audioURL,
            lastPlaybackPosition: 600, duration: 1800)
        // Direct assignment, not setCompleted(): that also pushes to the shared
        // iCloud sync coordinator. No save() either — iOS 27's test host aborts
        // on SwiftData saves, and a fetch on this context sees the insert anyway.
        model.isCompleted = completed
        container.mainContext.insert(model)

        let manager = EnhancedAudioManager.shared
        let previous = manager.currentEpisode
        manager.restoreLastEpisode()  // spend the one-shot restore so it can't overwrite ours
        manager.currentEpisode = ep
        defer { manager.currentEpisode = previous }

        let viewModel = HomeViewModel()
        viewModel.setModelContext(container.mainContext)
        try body(viewModel, ep)

        for _ in 0..<200 where !viewModel.hasLoadedUpNext {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(viewModel.hasLoadedUpNext, "the full load lands and replaces the seed")
        viewModel.cleanup()
    }

    @Test("The current episode is in Up Next as soon as Home appears")
    func seedsCurrentEpisode() async throws {
        try await withCurrentEpisode(completed: false) { viewModel, ep in
            // Synchronously after setModelContext — before any load task ran.
            #expect(!viewModel.hasLoadedUpNext)
            #expect(viewModel.upNextEpisodes.map(\.id) == [ep.id])
            #expect(viewModel.scoredUpNextEpisodes.first?.progressRatio == 600.0 / 1800.0)
        }
    }

    @Test("A finished current episode isn't seeded")
    func skipsCompletedEpisode() async throws {
        try await withCurrentEpisode(completed: true) { viewModel, _ in
            #expect(viewModel.upNextEpisodes.isEmpty)
            #expect(!viewModel.hasLoadedUpNext, "still loading, so the section shows nothing, not the empty state")
        }
    }
}

}
