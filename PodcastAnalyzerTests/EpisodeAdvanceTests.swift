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

    /// A short AAC file on disk, like a downloaded episode.
    private func localAudioFile(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("advance-\(UUID().uuidString).m4a")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
        ])
        let frames = AVAudioFrameCount(seconds * 44_100)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
        return url
    }

    @Test("A downloaded episode that plays to its real end stops and stays stopped")
    func localFileEndDoesNotReplay() async throws {
        try await withCleanManager(autoPlay: false) {
            let url = try localAudioFile(seconds: 2)
            defer { try? FileManager.default.removeItem(at: url) }
            let ep = episode("Local")
            manager.play(episode: ep, audioURL: url.absoluteString)

            // Real playback to the real end, no posted notification.
            for _ in 0..<100 where manager.isPlaying {
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(!manager.isPlaying, "the episode ended")
            try await Task.sleep(for: .seconds(2))

            #expect(!manager.isPlaying, "nothing restarted it")
            #expect(manager.player?.timeControlStatus != .playing)
            #expect(manager.currentTime == 0)
        }
    }

    @Test("An early end report on a downloaded file completes it instead of replaying")
    func localFileEarlyEndCompletes() async throws {
        try await withCleanManager(autoPlay: false) {
            let url = try localAudioFile(seconds: 30)
            defer { try? FileManager.default.removeItem(at: url) }
            manager.play(episode: episode("Local"), audioURL: url.absoluteString)

            // Wait until it's really playing, so the item knows its duration.
            for _ in 0..<50 where !(manager.player?.currentItem?.duration.seconds.isFinite ?? false)
                || (manager.player?.currentTime().seconds ?? 0) < 0.5 {
                try await Task.sleep(for: .milliseconds(100))
            }
            // Ends "at 0.5s of 30s": a stream would be retried, a file is done.
            try await finishCurrentEpisode()
            try await Task.sleep(for: .milliseconds(300))

            #expect(!manager.isPlaying)
            #expect(manager.player?.timeControlStatus != .playing)
            #expect(manager.currentTime == 0)
        }
    }

    // MARK: - Finish action, downloaded vs streamed

    enum Source: String, CaseIterable, CustomTestStringConvertible {
        case downloaded, streamed
        var testDescription: String { rawValue }
    }

    /// Starts `title` from a local file or a remote URL. A downloaded one is
    /// played until the item has loaded, so its end is judged against its
    /// real length. Returns the temp file to delete, if any.
    @discardableResult
    private func start(_ title: String, from source: Source) async throws -> URL? {
        let ep = episode(title)
        guard source == .downloaded else {
            start(ep)
            return nil
        }
        let url = try localAudioFile(seconds: 30)
        manager.play(episode: ep, audioURL: url.absoluteString)
        for _ in 0..<50 where !(manager.player?.currentItem?.duration.seconds.isFinite ?? false)
            || (manager.player?.currentTime().seconds ?? 0) < 0.3 {
            try await Task.sleep(for: .milliseconds(100))
        }
        return url
    }

    @Test("Finishing with nothing next stops at the start and keeps the episode loaded", arguments: Source.allCases)
    func finishStopsAtStart(source: Source) async throws {
        try await withCleanManager(autoPlay: false) {
            let file = try await start("A", from: source)
            defer { file.map { try? FileManager.default.removeItem(at: $0) } }
            manager.autoPlayCandidates = [episode("A"), episode("C")]

            try await finishCurrentEpisode()
            try await Task.sleep(for: .milliseconds(500))

            #expect(!manager.isPlaying)
            #expect(manager.player?.timeControlStatus != .playing, "nothing restarted it")
            #expect(manager.currentEpisode?.title == "A")
            #expect(manager.currentTime == 0)
            #expect(!manager.autoPlayCandidates.contains { $0.title == "A" }, "the finished episode is dropped even with autoplay off")
        }
    }

    @Test("Finishing writes a forced position == duration, which marks it played", arguments: Source.allCases)
    func finishMarksPlayed(source: Source) async throws {
        try await withCleanManager(autoPlay: false) {
            let file = try await start("A", from: source)
            defer { file.map { try? FileManager.default.removeItem(at: $0) } }
            var updates: [PlaybackPositionUpdate] = []
            let observer = NotificationCenter.default.addObserver(
                forName: .playbackPositionDidUpdate, object: nil, queue: nil
            ) { note in
                let update = note.userInfo?["update"] as? PlaybackPositionUpdate
                MainActor.assumeIsolated { update.map { updates.append($0) } }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            try await finishCurrentEpisode()

            let final = try #require(updates.last { $0.episodeTitle == "A" })
            #expect(final.duration > 0)
            #expect(final.position == final.duration)
            #expect(final.forceSync)
        }
    }

    @Test("Finishing plays the next queued episode on the same player", arguments: Source.allCases)
    func finishPlaysQueued(source: Source) async throws {
        try await withCleanManager(autoPlay: false) {
            let file = try await start("A", from: source)
            defer { file.map { try? FileManager.default.removeItem(at: $0) } }
            let player = try #require(manager.player)
            manager.queue = [episode("B")]

            try await finishCurrentEpisode()

            #expect(manager.currentEpisode?.title == "B")
            #expect(manager.isPlaying)
            #expect(manager.queue.isEmpty)
            #expect(manager.player === player)
        }
    }

    @Test("Finishing with autoplay on plays the top suggestion", arguments: Source.allCases)
    func finishAutoplays(source: Source) async throws {
        try await withCleanManager(autoPlay: true) {
            let file = try await start("A", from: source)
            defer { file.map { try? FileManager.default.removeItem(at: $0) } }

            let expected = try await finishCurrentEpisode(offering: [episode("A"), episode("C")])

            #expect(expected != nil)
            #expect(manager.currentEpisode?.id == expected?.id)
            #expect(manager.currentEpisode?.title != "A", "never replays the finished one")
            #expect(manager.isPlaying)
        }
    }

    @Test("Finishing with autoplay on but no suggestions stops at the start", arguments: Source.allCases)
    func finishAutoplayWithNothingStops(source: Source) async throws {
        try await withCleanManager(autoPlay: true) {
            let file = try await start("A", from: source)
            defer { file.map { try? FileManager.default.removeItem(at: $0) } }

            try await finishCurrentEpisode(offering: [episode("A")])

            #expect(!manager.isPlaying)
            #expect(manager.currentEpisode?.title == "A")
            #expect(manager.currentTime == 0)
        }
    }

    @Test("Sleep timer 'end of episode' stops at the finish", arguments: Source.allCases)
    func finishWithSleepTimerStops(source: Source) async throws {
        try await withCleanManager(autoPlay: true) {
            let file = try await start("A", from: source)
            defer { file.map { try? FileManager.default.removeItem(at: $0) } }
            manager.queue = [episode("B")]
            manager.setSleepTimer(.endOfEpisode)

            try await finishCurrentEpisode()

            #expect(!manager.isPlaying)
            #expect(manager.queue.map(\.title) == ["B"])
            #expect(manager.sleepTimerOption == .off)
        }
    }

    @Test("Tapping play on a finished episode replays it from the start", arguments: Source.allCases)
    func replayAfterFinish(source: Source) async throws {
        try await withCleanManager(autoPlay: false) {
            let file = try await start("A", from: source)
            defer { file.map { try? FileManager.default.removeItem(at: $0) } }
            try await finishCurrentEpisode()
            let ep = try #require(manager.currentEpisode)

            manager.play(episode: ep, audioURL: ep.audioURL)

            #expect(manager.isPlaying)
            #expect(manager.currentTime < 1)
        }
    }

    @Test("Resuming rewinds more the longer the pause was", arguments: [
        (30.0, 0.0), (59.0, 0.0), (60.0, 5.0), (3599.0, 5.0),
        (3600.0, 15.0), (86_399.0, 15.0), (86_400.0, 30.0), (604_800.0, 30.0),
    ])
    func resumeRewindScalesWithPause(pause: TimeInterval, rewind: TimeInterval) {
        #expect(EnhancedAudioManager.resumeRewind(afterPause: pause) == rewind)
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
