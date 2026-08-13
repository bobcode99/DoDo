//
//  PlayerInteractionFlowTests.swift
//  PodcastAnalyzerTests
//
//  Stage 3 of the user journey: the expanded player. Dragging the scrubber,
//  the skip buttons, the play/pause button, and the queue.
//
//  These drive `EnhancedAudioManager.shared` — a singleton, so the suite is
//  serialized and every test restores the state it touched. No AVPlayer is
//  ever created: the tests deliberately exercise the "restored episode, not
//  started yet" shape (`player == nil`), which is where the transport controls
//  used to silently no-op, and which needs no audio hardware or network.
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Journey: expanded player controls", .serialized)
struct PlayerInteractionFlowTests {

    // MARK: - Fixtures

    private func episode(
        title: String = "Episode 1",
        podcast: String = "Daily Tech",
        duration: Int? = 1800
    ) -> PlaybackEpisode {
        PlaybackEpisode(
            id: EpisodeKeyUtils.makeKey(podcastTitle: podcast, episodeTitle: title),
            title: title,
            podcastTitle: podcast,
            audioURL: "https://example.com/\(title).mp3",
            imageURL: nil,
            episodeDescription: nil,
            pubDate: nil,
            duration: duration,
            guid: nil
        )
    }

    /// Puts the shared manager in the "episode restored from last session, not
    /// started yet" state and hands back a reset closure for `defer`.
    private func stageRestoredEpisode(
        _ episode: PlaybackEpisode,
        playerDuration: TimeInterval = 0,
        currentTime: TimeInterval = 0
    ) -> () -> Void {
        let manager = EnhancedAudioManager.shared
        let previousEpisode = manager.currentEpisode
        let previousTime = manager.currentTime
        let previousDuration = manager.duration
        let previousPlaying = manager.isPlaying
        let previousQueue = manager.queue

        manager.currentEpisode = episode
        manager.currentTime = currentTime
        manager.duration = playerDuration
        manager.isPlaying = false

        return {
            manager.currentEpisode = previousEpisode
            manager.currentTime = previousTime
            manager.duration = previousDuration
            manager.isPlaying = previousPlaying
            manager.queue = previousQueue
        }
    }

    // MARK: - Dragging the scrubber

    @Test("Dragging the scrubber to the middle moves the playhead there")
    func dragToMiddleSeeks() {
        let reset = stageRestoredEpisode(episode())
        defer { reset() }
        let viewModel = ExpandedPlayerViewModel()

        // What SmoothScrubber hands over on release: the thumb position as a
        // fraction of the track.
        viewModel.seekToProgress(0.5)

        #expect(EnhancedAudioManager.shared.currentTime == 900)
        #expect(viewModel.progress == 0, "progress reads the player's own duration, still unmeasured")
    }

    @Test("The scrubber has a real scale before the first play")
    func scrubberScaleBeforeFirstPlay() {
        let reset = stageRestoredEpisode(episode(duration: 1800))
        defer { reset() }
        let viewModel = ExpandedPlayerViewModel()

        // No AVPlayer yet, so the player's measured duration is 0. Falling back
        // to the episode's declared length is what keeps the whole track from
        // collapsing into one second — a drag anywhere would otherwise land in
        // the first second of audio.
        #expect(viewModel.duration == 1800)
        #expect(!viewModel.isDurationLoading)

        viewModel.seekToProgress(0.25)
        #expect(EnhancedAudioManager.shared.currentTime == 450)
    }

    @Test("With no duration known at all, the scrubber reports itself as loading")
    func scrubberDisabledWhenDurationUnknown() {
        let reset = stageRestoredEpisode(episode(duration: nil))
        defer { reset() }
        let viewModel = ExpandedPlayerViewModel()

        #expect(viewModel.duration == 0)
        #expect(viewModel.isDurationLoading, "the scrubber dims and stops accepting drags")
    }

    @Test("Dragging to either end clamps to the episode instead of overshooting")
    func dragClampsAtBothEnds() {
        let reset = stageRestoredEpisode(episode(duration: 1800), currentTime: 600)
        defer { reset() }
        let manager = EnhancedAudioManager.shared

        manager.seek(to: 5000)
        #expect(manager.currentTime == 1800, "never past the end of the episode")

        manager.seek(to: -30)
        #expect(manager.currentTime == 0, "never before the start")
    }

    @Test("A drag lands on the exact requested second")
    func dragIsNotQuantized() {
        let reset = stageRestoredEpisode(episode(duration: 1800))
        defer { reset() }
        let manager = EnhancedAudioManager.shared

        manager.seek(to: 123.4)
        #expect(abs(manager.currentTime - 123.4) < 0.0001)
    }

    // MARK: - Skip buttons

    @Test("Skip forward and back work before the first play")
    func skipWorksBeforeFirstPlay() {
        let reset = stageRestoredEpisode(episode(duration: 1800), currentTime: 100)
        defer { reset() }
        let manager = EnhancedAudioManager.shared

        manager.skipForward(seconds: 30)
        #expect(manager.currentTime == 130, "the forward button used to no-op until the user pressed play")

        manager.skipBackward(seconds: 15)
        #expect(manager.currentTime == 115)
    }

    @Test("Skip forward near the end stops at the end, not past it")
    func skipForwardClampsToEnd() {
        let reset = stageRestoredEpisode(episode(duration: 1800), currentTime: 1790)
        defer { reset() }
        let manager = EnhancedAudioManager.shared

        manager.skipForward(seconds: 30)
        #expect(manager.currentTime == 1800)
    }

    @Test("Skip back at the very start stays at zero")
    func skipBackwardFloorsAtZero() {
        let reset = stageRestoredEpisode(episode(duration: 1800), currentTime: 5)
        defer { reset() }
        let manager = EnhancedAudioManager.shared

        manager.skipBackward(seconds: 15)
        #expect(manager.currentTime == 0)
    }

    @Test("Skip forward on an episode of unknown length still moves the playhead")
    func skipForwardWithoutDurationStillMoves() {
        let reset = stageRestoredEpisode(episode(duration: nil), currentTime: 60)
        defer { reset() }
        let manager = EnhancedAudioManager.shared

        manager.skipForward(seconds: 30)
        #expect(manager.currentTime == 90, "an unknown cap must not clamp every target to zero")
    }

    // MARK: - Play / pause button

    @Test("The play button toggles playback state")
    func playButtonToggles() {
        let reset = stageRestoredEpisode(episode())
        defer { reset() }
        let manager = EnhancedAudioManager.shared
        let viewModel = ExpandedPlayerViewModel()

        // Mid-playback pause: the only branch that doesn't need a real AVPlayer.
        manager.isPlaying = true
        #expect(viewModel.isPlaying)

        viewModel.togglePlayPause()
        #expect(!manager.isPlaying)
        #expect(!viewModel.isPlaying, "the view model reads through to the manager, no mirrored state")
    }

    @Test("Pausing keeps the playhead where the user left it")
    func pauseKeepsPosition() {
        let reset = stageRestoredEpisode(episode(duration: 1800), currentTime: 640)
        defer { reset() }
        let manager = EnhancedAudioManager.shared
        manager.isPlaying = true

        manager.pause()

        #expect(!manager.isPlaying)
        #expect(manager.currentTime == 640)
    }

    @Test("Playback speed changes are reflected back to the speed menu")
    func speedMenuRoundTrips() {
        let reset = stageRestoredEpisode(episode())
        defer { reset() }
        let manager = EnhancedAudioManager.shared
        let previousRate = manager.playbackRate
        defer { manager.setPlaybackRate(previousRate) }

        let viewModel = ExpandedPlayerViewModel()
        viewModel.setPlaybackSpeed(1.5)

        #expect(abs(viewModel.playbackSpeed - 1.5) < 0.0001)
        #expect(abs(manager.playbackRate - 1.5) < 0.0001)
    }

    // MARK: - Queue

    /// Queue mutations write through `PlaybackStateCoordinator.shared`. Point it
    /// at an in-memory container so the tests don't touch the host app's store,
    /// and put back whatever was there.
    private func withQueueStore(_ body: (PlaybackStateCoordinator) throws -> Void) throws {
        let schema = Schema([QueueItemModel.self, EpisodeDownloadModel.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let previous = PlaybackStateCoordinator.shared
        defer { PlaybackStateCoordinator.shared = previous }
        try body(PlaybackStateCoordinator(modelContext: container.mainContext))
    }

    @Test("Play Next puts an episode at the front of the queue")
    func playNextGoesFirst() throws {
        let reset = stageRestoredEpisode(episode(title: "Now Playing"))
        defer { reset() }
        let manager = EnhancedAudioManager.shared
        manager.queue = []

        try withQueueStore { _ in
            manager.addToQueue(episode(title: "Later"))
            manager.playNext(episode(title: "Jump The Line"))

            #expect(manager.queue.map(\.title) == ["Jump The Line", "Later"])
        }
    }

    @Test("Queueing the same episode twice doesn't duplicate it")
    func queueDedupes() throws {
        let reset = stageRestoredEpisode(episode(title: "Now Playing"))
        defer { reset() }
        let manager = EnhancedAudioManager.shared
        manager.queue = []

        try withQueueStore { _ in
            manager.addToQueue(episode(title: "Later"))
            manager.addToQueue(episode(title: "Later"))
            #expect(manager.queue.count == 1)

            // Nor can the episode that's already playing be queued behind itself.
            manager.addToQueue(episode(title: "Now Playing"))
            #expect(manager.queue.map(\.title) == ["Later"])
        }
    }

    @Test("Play Next on an episode already queued moves it instead of adding it")
    func playNextMovesExistingItem() throws {
        let reset = stageRestoredEpisode(episode(title: "Now Playing"))
        defer { reset() }
        let manager = EnhancedAudioManager.shared
        manager.queue = []

        try withQueueStore { _ in
            manager.addToQueue(episode(title: "A"))
            manager.addToQueue(episode(title: "B"))
            manager.playNext(episode(title: "B"))

            #expect(manager.queue.map(\.title) == ["B", "A"])
        }
    }

    @Test("Swiping a queue row away removes exactly that row")
    func removeFromQueueByIndex() throws {
        let reset = stageRestoredEpisode(episode(title: "Now Playing"))
        defer { reset() }
        let manager = EnhancedAudioManager.shared
        manager.queue = []

        try withQueueStore { _ in
            manager.addToQueue(episode(title: "A"))
            manager.addToQueue(episode(title: "B"))
            manager.addToQueue(episode(title: "C"))

            manager.removeFromQueue(at: 1)
            #expect(manager.queue.map(\.title) == ["A", "C"])

            // An out-of-range index from a stale row must be ignored, not crash.
            manager.removeFromQueue(at: 99)
            #expect(manager.queue.map(\.title) == ["A", "C"])
        }
    }

    @Test("Dragging a queue row reorders the queue")
    func moveInQueueReorders() throws {
        let reset = stageRestoredEpisode(episode(title: "Now Playing"))
        defer { reset() }
        let manager = EnhancedAudioManager.shared
        manager.queue = []

        try withQueueStore { _ in
            manager.addToQueue(episode(title: "A"))
            manager.addToQueue(episode(title: "B"))
            manager.addToQueue(episode(title: "C"))

            // SwiftUI's onMove for "drag C above A".
            manager.moveInQueue(from: IndexSet(integer: 2), to: 0)
            #expect(manager.queue.map(\.title) == ["C", "A", "B"])
        }
    }

    @Test("The queue survives a relaunch")
    func queueIsPersisted() throws {
        let reset = stageRestoredEpisode(episode(title: "Now Playing"))
        defer { reset() }
        let manager = EnhancedAudioManager.shared
        manager.queue = []

        try withQueueStore { coordinator in
            manager.addToQueue(episode(title: "A"))
            manager.addToQueue(episode(title: "B"))

            let restored = coordinator.restoreQueue()
            #expect(restored.map(\.title) == ["A", "B"], "order is restored, not just membership")
            #expect(restored.first?.audioURL == "https://example.com/A.mp3")
        }
    }

    @Test("Clearing the queue empties the stored queue too")
    func clearQueueClearsStore() throws {
        let reset = stageRestoredEpisode(episode(title: "Now Playing"))
        defer { reset() }
        let manager = EnhancedAudioManager.shared
        manager.queue = []

        try withQueueStore { coordinator in
            manager.addToQueue(episode(title: "A"))
            manager.clearQueue()

            #expect(manager.queue.isEmpty)
            #expect(coordinator.restoreQueue().isEmpty)
        }
    }
}
