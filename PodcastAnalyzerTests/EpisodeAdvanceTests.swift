//
//  EpisodeAdvanceTests.swift
//  PodcastAnalyzerTests
//
//  What happens when an episode finishes: queue first, then Up Next autoplay,
//  else stop at the start. Drives the real path — `play(...)` builds an
//  AVPlayer, and the test posts `AVPlayerItemDidPlayToEndTime` for its item,
//  exactly what AVFoundation does at the end of the audio.
//
//  Episodes use remote URLs (nothing downloaded), the case that used to stall:
//  the player was torn down and rebuilt between episodes, and in the
//  background the next stream never started.
//
//  `EnhancedAudioManager.shared` is a singleton, so this suite is nested in
//  the serialized player suite (a sibling suite would run in parallel with it
//  and see a live player) and every test restores what it touched.
//  `PlaybackStateCoordinator.shared` is cleared for the duration so no queue
//  write reaches the app's store, and saved positions read as 0.
//
//  The host app is running underneath: its Home screen rebuilds the autoplay
//  candidates whenever the queue changes. Setup waits that out, and the
//  assertions avoid depending on the candidate list after an advance.
//

import AVFoundation
import Foundation
import Testing
@testable import PodcastAnalyzer

extension PlayerInteractionFlowTests {

@MainActor
@Suite("Episode advance at end of playback")
struct EpisodeAdvance {

    private let manager = EnhancedAudioManager.shared

    private func episode(_ title: String, podcast: String = "Daily Tech") -> PlaybackEpisode {
        PlaybackEpisode(
            id: EpisodeKeyUtils.makeKey(podcastTitle: podcast, episodeTitle: title),
            title: title,
            podcastTitle: podcast,
            audioURL: "https://example.com/\(title).mp3",
            imageURL: nil,
            episodeDescription: nil,
            pubDate: nil,
            duration: 1800,
            guid: nil
        )
    }

    /// Runs `body` with the manager stopped and empty, then restores it.
    private func withCleanManager(autoPlay: Bool, _ body: () async throws -> Void) async throws {
        let defaults = UserDefaults.standard
        let previousAutoPlay = defaults.object(forKey: "autoPlayNextEpisode")
        let previousCoordinator = PlaybackStateCoordinator.shared
        let previousQueue = manager.queue
        let previousCandidates = manager.autoPlayCandidates

        PlaybackStateCoordinator.shared = nil
        defaults.set(autoPlay, forKey: "autoPlayNextEpisode")
        manager.stop()
        manager.queue = []
        manager.autoPlayCandidates = []
        manager.setSleepTimer(.off)
        // Let the host app's Up Next reload (triggered by the queue reset) land
        // before the test sets its own candidates.
        try await Task.sleep(for: .milliseconds(500))

        defer {
            manager.stop()
            manager.setSleepTimer(.off)
            manager.queue = previousQueue
            manager.autoPlayCandidates = previousCandidates
            defaults.set(previousAutoPlay, forKey: "autoPlayNextEpisode")
            PlaybackStateCoordinator.shared = previousCoordinator
        }
        try await body()
    }

    private func start(_ episode: PlaybackEpisode) {
        manager.play(episode: episode, audioURL: episode.audioURL)
    }

    /// Posts the end-of-item notification for the loaded item and waits for
    /// the manager to react (its observer runs on a task, not inline).
    /// `candidates` are set at the last moment, and the return value is what
    /// the manager is about to pick: the host app's Up Next can rebuild the
    /// list at any time, so assert against the snapshot, not a fixed title.
    @discardableResult
    private func finishCurrentEpisode(offering candidates: [PlaybackEpisode]? = nil) async throws -> PlaybackEpisode? {
        let item = try #require(manager.player?.currentItem)
        let finished = manager.currentEpisode?.id
        // Let the observer task subscribe before posting.
        try await Task.sleep(for: .milliseconds(100))
        if let candidates { manager.autoPlayCandidates = candidates }
        let expectedNext = manager.autoPlayCandidates.first { $0.id != finished }
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: item)
        for _ in 0..<100 {
            if !manager.isPlaying || manager.currentEpisode?.id != finished { return expectedNext }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("manager never reacted to the end of the episode")
        return expectedNext
    }

    // MARK: - Queue

    @Test("A finished stream plays the next queued episode on the same player")
    func queueAdvanceReusesPlayer() async throws {
        try await withCleanManager(autoPlay: false) {
            start(episode("A"))
            let player = try #require(manager.player)
            manager.queue = [episode("B")]

            try await finishCurrentEpisode()

            #expect(manager.currentEpisode?.title == "B")
            #expect(manager.isPlaying)
            #expect(manager.queue.isEmpty)
            #expect(manager.player === player, "the player is kept; only its item is swapped")
            let url = (manager.player?.currentItem?.asset as? AVURLAsset)?.url
            #expect(url?.absoluteString == "https://example.com/B.mp3")
        }
    }

    @Test("The queue wins over autoplay suggestions")
    func queueBeatsAutoplay() async throws {
        try await withCleanManager(autoPlay: true) {
            start(episode("A"))
            manager.queue = [episode("Queued")]
            manager.autoPlayCandidates = [episode("Suggested")]

            try await finishCurrentEpisode()

            #expect(manager.currentEpisode?.title == "Queued")
            #expect(manager.queue.isEmpty)
        }
    }

    // MARK: - Autoplay

    @Test("With autoplay on, the top Up Next suggestion plays and the finished one is dropped")
    func autoplayPicksTopCandidate() async throws {
        try await withCleanManager(autoPlay: true) {
            start(episode("A"))
            let player = try #require(manager.player)
            let expected = try await finishCurrentEpisode(offering: [episode("A"), episode("C"), episode("D")])

            #expect(expected != nil)
            #expect(manager.currentEpisode?.id == expected?.id, "normally C, unless the host's Up Next just replaced the list")
            #expect(manager.isPlaying)
            #expect(!manager.autoPlayCandidates.contains { $0.title == "A" }, "the finished episode is never offered again")
            #expect(manager.player === player)
        }
    }

    @Test("With autoplay off and no queue, playback stops rewound to the start")
    func nothingNextStopsAtStart() async throws {
        try await withCleanManager(autoPlay: false) {
            start(episode("A"))
            manager.autoPlayCandidates = [episode("C")]

            try await finishCurrentEpisode()

            #expect(!manager.isPlaying)
            #expect(manager.currentEpisode?.title == "A", "the finished episode stays loaded for replay")
            #expect(manager.currentTime == 0)
        }
    }

    // MARK: - Sleep timer

    @Test("Sleep timer 'end of episode' stops instead of advancing")
    func sleepTimerEndOfEpisodeStops() async throws {
        try await withCleanManager(autoPlay: true) {
            start(episode("A"))
            manager.queue = [episode("B")]
            manager.setSleepTimer(.endOfEpisode)

            try await finishCurrentEpisode()

            #expect(!manager.isPlaying)
            #expect(manager.queue.map(\.title) == ["B"], "queue untouched for next time")
            #expect(manager.sleepTimerOption == .off, "the timer is spent")
        }
    }

    // MARK: - Switching episodes

    @Test("Starting another episode mid-play swaps the item on the same player")
    func switchingEpisodesReusesPlayer() async throws {
        try await withCleanManager(autoPlay: false) {
            start(episode("A"))
            let player = try #require(manager.player)
            let firstItem = player.currentItem

            start(episode("B"))

            #expect(manager.player === player)
            #expect(player.currentItem !== firstItem)
            #expect(manager.currentEpisode?.title == "B")
            #expect(manager.isPlaying)
        }
    }

    @Test("A stale end notification from the previous item is ignored")
    func previousItemEndIsIgnored() async throws {
        try await withCleanManager(autoPlay: false) {
            start(episode("A"))
            let oldItem = try #require(manager.player?.currentItem)
            start(episode("B"))
            manager.queue = [episode("C")]
            try await Task.sleep(for: .milliseconds(100))

            NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: oldItem)
            try await Task.sleep(for: .milliseconds(200))

            #expect(manager.currentEpisode?.title == "B", "only the loaded item's end advances")
            #expect(manager.queue.map(\.title) == ["C"])
        }
    }

    @Test("Stopping tears the player down; the next play builds a fresh one")
    func stopReleasesPlayer() async throws {
        try await withCleanManager(autoPlay: false) {
            start(episode("A"))
            let player = try #require(manager.player)

            manager.stop()
            #expect(manager.player == nil)

            start(episode("B"))
            #expect(manager.player != nil)
            #expect(manager.player !== player)
        }
    }
}

}
