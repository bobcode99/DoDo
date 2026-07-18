//
//  PlaybackProgressSyncTests.swift
//  PodcastAnalyzerTests
//
//  Verifies the iCloud playback-progress sync logic: push throttling (so a
//  playing device doesn't hammer CloudKit every 5s) and last-writer-wins
//  merge of incoming remote changes into local EpisodeDownloadModel state.
//  Runs entirely against an in-memory SwiftData container — no live CloudKit
//  network access is needed or used.
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

@Suite("Playback progress sync")
struct PlaybackProgressSyncTests {

    // MARK: - Throttle logic

    @Test("First push is never throttled")
    func firstPushAlwaysAllowed() {
        #expect(PlaybackProgressMerge.shouldPush(
            now: Date(), lastPushedAt: nil, minInterval: 30, force: false
        ))
    }

    @Test("Push within the throttle window is skipped")
    func pushWithinWindowSkipped() {
        let last = Date()
        let now = last.addingTimeInterval(10)
        #expect(!PlaybackProgressMerge.shouldPush(
            now: now, lastPushedAt: last, minInterval: 30, force: false
        ))
    }

    @Test("Push after the throttle window is allowed")
    func pushAfterWindowAllowed() {
        let last = Date()
        let now = last.addingTimeInterval(31)
        #expect(PlaybackProgressMerge.shouldPush(
            now: now, lastPushedAt: last, minInterval: 30, force: false
        ))
    }

    @Test("Force always pushes, even mid-window")
    func forceBypassesThrottle() {
        let last = Date()
        let now = last.addingTimeInterval(1)
        #expect(PlaybackProgressMerge.shouldPush(
            now: now, lastPushedAt: last, minInterval: 30, force: true
        ))
    }

    // MARK: - Last-writer-wins comparison

    @Test("Remote strictly newer than local wins")
    func remoteNewerWins() {
        let local = Date()
        let remote = local.addingTimeInterval(5)
        #expect(PlaybackProgressMerge.isRemoteNewer(remoteUpdatedAt: remote, localUpdatedAt: local))
    }

    @Test("Remote older than local loses")
    func remoteOlderLoses() {
        let local = Date()
        let remote = local.addingTimeInterval(-5)
        #expect(!PlaybackProgressMerge.isRemoteNewer(remoteUpdatedAt: remote, localUpdatedAt: local))
    }

    @Test("Equal timestamps favor local (no redundant overwrite)")
    func tieFavorsLocal() {
        let timestamp = Date()
        #expect(!PlaybackProgressMerge.isRemoteNewer(remoteUpdatedAt: timestamp, localUpdatedAt: timestamp))
    }

    @Test("Remote wins when local has never been stamped")
    func remoteWinsAgainstNilLocal() {
        #expect(PlaybackProgressMerge.isRemoteNewer(remoteUpdatedAt: Date(), localUpdatedAt: nil))
    }

    // MARK: - End-to-end push (in-memory SwiftData)

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([EpisodeDownloadModel.self, PlaybackProgressModel.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    @Test("push() creates a synced record mirroring the local episode")
    func pushCreatesRecord() throws {
        let container = try makeContainer()
        let coordinator = PlaybackProgressSyncCoordinator()
        coordinator.setModelContainer(container)

        let episode = EpisodeDownloadModel(
            episodeTitle: "Episode 1", podcastTitle: "Show", audioURL: "https://example.com/1.mp3",
            lastPlaybackPosition: 42, duration: 100
        )
        container.mainContext.insert(episode)
        try container.mainContext.save()

        coordinator.push(from: episode, force: true)

        let id = episode.id
        let records = try container.mainContext.fetch(
            FetchDescriptor<PlaybackProgressModel>(predicate: #Predicate { $0.id == id })
        )
        #expect(records.count == 1)
        #expect(records.first?.lastPlaybackPosition == 42)
        #expect(records.first?.duration == 100)
    }

    @MainActor
    @Test("push() without force is throttled on the second call")
    func pushThrottledOnSecondCall() throws {
        let container = try makeContainer()
        let coordinator = PlaybackProgressSyncCoordinator()
        coordinator.setModelContainer(container)

        let episode = EpisodeDownloadModel(
            episodeTitle: "Episode 1", podcastTitle: "Show", audioURL: "https://example.com/1.mp3",
            lastPlaybackPosition: 10, duration: 100
        )
        container.mainContext.insert(episode)
        try container.mainContext.save()

        coordinator.push(from: episode, force: false)
        episode.lastPlaybackPosition = 20
        coordinator.push(from: episode, force: false)  // should be skipped (< 30s later)

        let id = episode.id
        let records = try container.mainContext.fetch(
            FetchDescriptor<PlaybackProgressModel>(predicate: #Predicate { $0.id == id })
        )
        #expect(records.first?.lastPlaybackPosition == 10, "second push should have been throttled")
    }

    @MainActor
    @Test("apply() overwrites local state when the remote row is newer")
    func applyOverwritesWhenNewer() throws {
        let container = try makeContainer()
        let coordinator = PlaybackProgressSyncCoordinator()
        coordinator.setModelContainer(container)

        let local = EpisodeDownloadModel(
            episodeTitle: "Episode 1", podcastTitle: "Show", audioURL: "https://example.com/1.mp3",
            lastPlaybackPosition: 10, duration: 100
        )
        local.progressUpdatedAt = Date().addingTimeInterval(-60)

        let remote = PlaybackProgressModel(
            id: local.id, lastPlaybackPosition: 55, duration: 100, isCompleted: false,
            playCount: 1, lastPlayedDate: Date(), updatedAt: Date(), deviceName: "Other Mac"
        )

        coordinator.apply(remote, to: local)

        #expect(local.lastPlaybackPosition == 55)
        #expect(local.progressUpdatedAt == remote.updatedAt)
    }

    @MainActor
    @Test("mergeIncomingChanges() skips rows that aren't newer than local state")
    func mergeSkipsStaleRemote() throws {
        let container = try makeContainer()
        let coordinator = PlaybackProgressSyncCoordinator()
        coordinator.setModelContainer(container)

        let staleUpdate = Date().addingTimeInterval(-120)
        let freshUpdate = Date()

        let local = EpisodeDownloadModel(
            episodeTitle: "Episode 1", podcastTitle: "Show", audioURL: "https://example.com/1.mp3",
            lastPlaybackPosition: 90, duration: 100
        )
        local.progressUpdatedAt = freshUpdate
        container.mainContext.insert(local)

        let staleRemote = PlaybackProgressModel(
            id: local.id, lastPlaybackPosition: 5, duration: 100, updatedAt: staleUpdate
        )
        container.mainContext.insert(staleRemote)
        try container.mainContext.save()

        coordinator.mergeIncomingChanges()

        #expect(local.lastPlaybackPosition == 90, "a stale remote row must not overwrite newer local progress")
    }

    @MainActor
    @Test("mergeIncomingChanges() applies rows that are newer than local state")
    func mergeAppliesFreshRemote() throws {
        let container = try makeContainer()
        let coordinator = PlaybackProgressSyncCoordinator()
        coordinator.setModelContainer(container)

        let local = EpisodeDownloadModel(
            episodeTitle: "Episode 1", podcastTitle: "Show", audioURL: "https://example.com/1.mp3",
            lastPlaybackPosition: 5, duration: 100
        )
        local.progressUpdatedAt = Date().addingTimeInterval(-120)
        container.mainContext.insert(local)

        let freshRemote = PlaybackProgressModel(
            id: local.id, lastPlaybackPosition: 77, duration: 100, updatedAt: Date()
        )
        container.mainContext.insert(freshRemote)
        try container.mainContext.save()

        coordinator.mergeIncomingChanges()

        #expect(local.lastPlaybackPosition == 77)
    }

    @MainActor
    @Test("mergeIncomingChanges() creates a local EpisodeDownloadModel for an episode never seen on this device")
    func mergeCreatesMissingLocalModel() throws {
        let container = try makeContainer()
        let coordinator = PlaybackProgressSyncCoordinator()
        coordinator.setModelContainer(container)

        // No local EpisodeDownloadModel exists yet — this episode was only
        // ever started on another device.
        let episodeId = EpisodeKeyUtils.makeKey(podcastTitle: "Show", episodeTitle: "Episode 1")
        let remote = PlaybackProgressModel(
            id: episodeId, lastPlaybackPosition: 42, duration: 100, updatedAt: Date()
        )
        container.mainContext.insert(remote)
        try container.mainContext.save()

        coordinator.mergeIncomingChanges()

        let created = try container.mainContext.fetch(
            FetchDescriptor<EpisodeDownloadModel>(predicate: #Predicate { $0.id == episodeId })
        ).first
        #expect(created != nil, "should have created a local placeholder row instead of dropping the sync")
        #expect(created?.lastPlaybackPosition == 42)
        #expect(created?.podcastTitle == "Show")
        #expect(created?.episodeTitle == "Episode 1")
    }
}
