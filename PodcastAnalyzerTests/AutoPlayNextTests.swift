//
//  AutoPlayNextTests.swift
//  PodcastAnalyzerTests
//
//  What plays when an episode ends, including after a widget play that
//  cold-launched the app in the background: no screen ever loads there, so
//  the candidates have to come back from disk and the played check has to work
//  without Home having run.
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Auto-play next", .serialized)
struct AutoPlayNextTests {

    private func episode(_ title: String, podcast: String = "Show") -> PlaybackEpisode {
        PlaybackEpisode(
            id: "\(podcast)\u{1F}\(title)",
            title: title,
            podcastTitle: podcast,
            audioURL: "https://example.com/\(title).mp3",
            imageURL: "https://example.com/\(title).jpg",
            episodeDescription: String(repeating: "Long show notes. ", count: 200),
            pubDate: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 1800,
            guid: "guid-\(title)"
        )
    }

    private func freshDefaults() -> UserDefaults {
        let name = "AutoPlayNextTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Choosing the next episode

    @Test("The next episode is the first in Up Next order")
    func picksFirstInOrder() {
        let next = EnhancedAudioManager.nextAutoPlayEpisode(
            from: [episode("A"), episode("B"), episode("C")],
            excluding: "Show\u{1F}Current", isCompleted: { _ in false }
        )
        #expect(next?.title == "A")
    }

    @Test("The episode that just ended is never picked again")
    func skipsJustEnded() {
        let next = EnhancedAudioManager.nextAutoPlayEpisode(
            from: [episode("A"), episode("B")],
            excluding: episode("A").id, isCompleted: { _ in false }
        )
        #expect(next?.title == "B")
    }

    @Test("An episode finished since the list was saved is skipped")
    func skipsFinishedSinceSaved() {
        let next = EnhancedAudioManager.nextAutoPlayEpisode(
            from: [episode("A"), episode("B"), episode("C")],
            excluding: nil, isCompleted: { ["A", "B"].contains($0.title) }
        )
        #expect(next?.title == "C")
    }

    @Test("Nothing plays when there's no candidate left", arguments: [
        ([String](), [String]()),          // empty list
        (["Current"], [String]()),          // only the episode that just ended
        (["A", "B"], ["A", "B"]),           // everything already finished
    ])
    func nothingLeft(titles: [String], finished: [String]) {
        let next = EnhancedAudioManager.nextAutoPlayEpisode(
            from: titles.map { episode($0) },
            excluding: episode("Current").id, isCompleted: { finished.contains($0.title) }
        )
        #expect(next == nil)
    }

    // MARK: - Surviving a cold launch

    @Test("Candidates survive a relaunch, in order, without their show notes")
    func candidatesSurviveRelaunch() throws {
        let defaults = freshDefaults()
        let saved = [episode("A", podcast: "One"), episode("B", podcast: "Two")]

        EnhancedAudioManager.saveAutoPlayCandidates(saved, to: defaults)
        let restored = EnhancedAudioManager.loadAutoPlayCandidates(from: defaults)

        #expect(restored.map(\.id) == saved.map(\.id))
        let first = try #require(restored.first)
        #expect(first.audioURL == "https://example.com/A.mp3", "playback needs the audio URL")
        #expect(first.imageURL == "https://example.com/A.jpg")
        #expect(first.duration == 1800)
        #expect(first.guid == "guid-A")
        #expect(first.episodeDescription == nil, "show notes are dropped to keep the saved list small")
    }

    @Test("A first launch with nothing saved has no candidates")
    func nothingSaved() {
        #expect(EnhancedAudioManager.loadAutoPlayCandidates(from: freshDefaults()).isEmpty)
    }

    @Test("Unreadable saved candidates load as none instead of crashing")
    func corruptSaved() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "autoPlayCandidates")
        #expect(EnhancedAudioManager.loadAutoPlayCandidates(from: defaults).isEmpty)
    }

    @Test("Updating the candidates in the player saves them for the next launch")
    func playerSavesOnUpdate() {
        let manager = EnhancedAudioManager.shared
        let previous = manager.autoPlayCandidates
        defer { manager.updateAutoPlayCandidates(previous) }  // the host's real settings

        manager.updateAutoPlayCandidates([episode("X"), episode("Y")])
        #expect(EnhancedAudioManager.loadAutoPlayCandidates().map(\.title) == ["X", "Y"])

        manager.removeFromAutoPlayCandidates(episode("X").id)
        #expect(EnhancedAudioManager.loadAutoPlayCandidates().map(\.title) == ["Y"],
                "an episode that finished must not come back after a relaunch")
    }

    // MARK: - The played check auto-play relies on

    private func withCoordinator(_ body: (PlaybackStateCoordinator) throws -> Void) throws {
        let schema = Schema([EpisodeDownloadModel.self, QueueItemModel.self, PlaybackProgressModel.self])
        // A throwaway file, not in-memory: on OS 27, hosted tests that fetch
        // from an in-memory SwiftData store abort with "No eligible
        // connection available".
        let url = URL.temporaryDirectory.appending(path: "AutoPlayNextTests-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        let previous = PlaybackStateCoordinator.shared
        defer { PlaybackStateCoordinator.shared = previous }
        try body(PlaybackStateCoordinator(modelContext: container.mainContext))
    }

    private func update(_ title: String, position: TimeInterval) -> PlaybackPositionUpdate {
        PlaybackPositionUpdate(
            episodeTitle: title, podcastTitle: "Show", position: position, duration: 1800,
            audioURL: "https://example.com/\(title).mp3")
    }

    @Test("An episode that played to the end reads as played; others don't")
    func isCompletedLookup() throws {
        try withCoordinator { coordinator in
            coordinator.savePlaybackPosition(update: update("Finished", position: 1800))
            coordinator.savePlaybackPosition(update: update("Halfway", position: 900))

            #expect(PlaybackStateCoordinator.isCompleted(podcastTitle: "Show", episodeTitle: "Finished"))
            #expect(!PlaybackStateCoordinator.isCompleted(podcastTitle: "Show", episodeTitle: "Halfway"))
            #expect(!PlaybackStateCoordinator.isCompleted(podcastTitle: "Show", episodeTitle: "Never played"))
        }
    }

    @Test("With a finished episode saved as a candidate, auto-play moves on to the next one")
    func staleCandidateSkippedEndToEnd() throws {
        try withCoordinator { coordinator in
            coordinator.savePlaybackPosition(update: update("A", position: 1800))

            let next = EnhancedAudioManager.nextAutoPlayEpisode(
                from: [episode("A"), episode("B")], excluding: episode("Current").id,
                isCompleted: { PlaybackStateCoordinator.isCompleted(podcastTitle: $0.podcastTitle, episodeTitle: $0.title) }
            )
            #expect(next?.title == "B")
        }
    }
}
