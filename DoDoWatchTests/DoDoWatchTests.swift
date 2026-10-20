//
//  DoDoWatchTests.swift
//  DoDoWatchTests
//
//  Runs on a watchOS simulator inside the DoDoWatch app. Covers the logic the
//  watch screens rely on: what Up Next shows, which phone update wins, how a
//  phone context decodes, and which file an episode plays from.
//

import Foundation
import Testing
@testable import DoDoWatch

@Suite("Up Next on the watch")
struct UpNextMergeTests {

    private func phone(_ title: String) -> PlaybackEpisode {
        PlaybackEpisode(
            id: "Show\u{1F}\(title)", title: title, podcastTitle: "Show",
            audioURL: "https://example.com/\(title).mp3")
    }

    private func queued(_ title: String) -> WatchPlayableEpisode {
        WatchPlayableEpisode(playbackEpisode: phone(title))
    }

    @Test("The Play Next queue leads, then the phone's list in its order")
    func queueThenPhone() {
        let merged = UpNextRows.merged(queue: [queued("Q")], phoneUpNext: [phone("A"), phone("B")])
        #expect(merged.map(\.title) == ["Q", "A", "B"])
    }

    @Test("An episode in both lists appears once, in its queue position")
    func dropsRepeats() {
        let merged = UpNextRows.merged(
            queue: [queued("B")], phoneUpNext: [phone("A"), phone("B"), phone("A")])
        #expect(merged.map(\.title) == ["B", "A"])
    }

    @Test("With nothing from either side the list is empty")
    func empty() {
        #expect(UpNextRows.merged(queue: [], phoneUpNext: []).isEmpty)
    }
}

@Suite("Phone context")
struct PhoneContextTests {

    private func snapshot(at date: Date, time: TimeInterval = 10) -> WidgetPlaybackData {
        WidgetPlaybackData(
            episodeTitle: "Ep", podcastTitle: "Show", imageURL: nil, audioURL: nil,
            currentTime: time, duration: 100, isPlaying: true, lastUpdated: date)
    }

    @Test("A late context older than the shown one is ignored")
    func olderSnapshotLoses() {
        let now = Date.now
        #expect(!WatchSessionManager.isNewer(snapshot(at: now.addingTimeInterval(-5)), than: snapshot(at: now)))
        #expect(WatchSessionManager.isNewer(snapshot(at: now.addingTimeInterval(5)), than: snapshot(at: now)))
        #expect(WatchSessionManager.isNewer(snapshot(at: now), than: nil))
    }

    @Test("Both parts decode from one context")
    func decodesBoth() throws {
        let encoder = JSONEncoder()
        let upNext = [PlaybackEpisode(id: "Show\u{1F}A", title: "A", podcastTitle: "Show", audioURL: "u")]
        let context: [String: Any] = [
            WatchMessageKey.nowPlaying: try encoder.encode(snapshot(at: .now, time: 42)),
            WatchMessageKey.upNext: try encoder.encode(upNext),
        ]

        let decoded = PhoneContext(context)

        #expect(decoded.nowPlaying?.currentTime == 42)
        #expect(decoded.upNext?.map(\.title) == ["A"])
    }

    @Test("A context from an older phone build has no Up Next, which leaves the list alone")
    func missingUpNextIsNil() throws {
        let context: [String: Any] = [
            WatchMessageKey.nowPlaying: try JSONEncoder().encode(snapshot(at: .now))
        ]
        let decoded = PhoneContext(context)
        #expect(decoded.nowPlaying != nil)
        #expect(decoded.upNext == nil, "nil, not [] — an empty list would wipe the rows")
    }
}

@Suite("Watch episode")
struct WatchPlayableEpisodeTests {

    private let episode = WatchPlayableEpisode(
        id: "x", title: "Ep 1", podcastTitle: "Show", audioURL: "https://example.com/1.mp3")

    @Test("Progress key matches the phone's composite key")
    func progressKey() {
        #expect(episode.progressKey == "Show\u{1F}Ep 1")
    }

    @Test("An episode with no art of its own shows the show's")
    func fallsBackToShowArt() {
        let bare = PodcastEpisodeInfo(title: "Ep", audioURL: "https://example.com/1.mp3")
        let own = PodcastEpisodeInfo(title: "Ep", audioURL: "https://example.com/1.mp3", imageURL: "ep.jpg")
        #expect(WatchPlayableEpisode(episode: bare, podcastTitle: "Show", podcastImageURL: "show.jpg")?.imageURL == "show.jpg")
        #expect(WatchPlayableEpisode(episode: own, podcastTitle: "Show", podcastImageURL: "show.jpg")?.imageURL == "ep.jpg")
    }

    @Test("Survives a relaunch: encodes and decodes unchanged")
    func codableRoundTrip() throws {
        var saved = episode
        saved.imageURL = "https://example.com/art.jpg"
        let data = try JSONEncoder().encode(saved)
        #expect(try JSONDecoder().decode(WatchPlayableEpisode.self, from: data) == saved)
    }

    @Test("Plays the downloaded file when it exists, the stream otherwise")
    func prefersLocalFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).mp3")
        try Data([0]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        var downloaded = episode
        downloaded.localPath = file.path(percentEncoded: false)
        #expect(downloaded.playbackURL?.isFileURL == true)

        var missing = episode
        missing.localPath = "/nonexistent/\(UUID().uuidString).mp3"
        #expect(missing.playbackURL?.absoluteString == "https://example.com/1.mp3", "a vanished file falls back to streaming")
    }
}

@Suite("Hand-off to iPhone")
struct HandOffTests {

    @Test("The play command carries the episode and the watch's position intact")
    func playRoundTrip() throws {
        let episode = PlaybackEpisode(
            id: "Show\u{1F}Ep", title: "Ep", podcastTitle: "Show", audioURL: "https://example.com/1.mp3")
        let command = WatchCommand.play(episode, at: 754.5)
        let decoded = try JSONDecoder().decode(WatchCommand.self, from: JSONEncoder().encode(command))
        #expect(decoded == command)
    }
}
