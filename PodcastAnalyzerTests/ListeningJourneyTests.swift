//
//  ListeningJourneyTests.swift
//  PodcastAnalyzerTests
//
//  Stage 2 of the user journey: start an episode → the app remembers where you
//  are → the Library and Up Next show it as started → finishing it marks it
//  played → replaying it resets that.
//
//  Everything runs through `PlaybackStateCoordinator.savePlaybackPosition`,
//  which is the single write path for playback progress: `EnhancedAudioManager`
//  posts `.playbackPositionDidUpdate` on every tick, pause, and seek, and the
//  coordinator turns that into SwiftData state. Tests call it directly rather
//  than posting the notification, because every live coordinator in the process
//  — including the host app's, backed by the real store — observes that name.
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Journey: listen → library shows progress")
struct ListeningJourneyTests {

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([EpisodeDownloadModel.self, QueueItemModel.self, PlaybackProgressModel.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func update(
        position: TimeInterval,
        duration: TimeInterval,
        episode: String = "Episode 1",
        podcast: String = "Daily Tech",
        forceSync: Bool = false
    ) -> PlaybackPositionUpdate {
        PlaybackPositionUpdate(
            episodeTitle: episode,
            podcastTitle: podcast,
            position: position,
            duration: duration,
            audioURL: "https://example.com/1.mp3",
            forceSync: forceSync
        )
    }

    /// Non-throwing so it can be used inside `#expect`, whose macro expansion
    /// doesn't carry the enclosing throwing context.
    private func fetchEpisode(
        _ context: ModelContext,
        podcast: String = "Daily Tech",
        episode: String = "Episode 1"
    ) -> EpisodeDownloadModel? {
        let key = EpisodeKeyUtils.makeKey(podcastTitle: podcast, episodeTitle: episode)
        return try? context.fetch(FetchDescriptor<EpisodeDownloadModel>(
            predicate: #Predicate { $0.id == key }
        )).first
    }

    /// Installs a coordinator bound to `container` and restores whatever was
    /// there before — `PlaybackStateCoordinator.init` claims the global
    /// `shared` slot, which the host app also uses.
    private func withCoordinator(
        _ container: ModelContainer,
        _ body: (PlaybackStateCoordinator, ModelContext) throws -> Void
    ) rethrows {
        let previous = PlaybackStateCoordinator.shared
        defer { PlaybackStateCoordinator.shared = previous }
        let coordinator = PlaybackStateCoordinator(modelContext: container.mainContext)
        try body(coordinator, container.mainContext)
    }

    // MARK: - Starting an episode

    @Test("Playing an episode for the first time creates its library row with progress")
    func firstPlayCreatesEpisodeRow() throws {
        let container = try makeContainer()
        try withCoordinator(container) { coordinator, context in
            #expect(fetchEpisode(context) == nil, "nothing stored before the first play")

            coordinator.savePlaybackPosition(update: update(position: 42, duration: 1800))

            let model = try #require(fetchEpisode(context))
            #expect(model.lastPlaybackPosition == 42)
            #expect(model.duration == 1800, "the measured player duration wins over RSS metadata")
            #expect(model.audioURL == "https://example.com/1.mp3")
            #expect(model.lastPlayedDate != nil)
            #expect(model.progressUpdatedAt != nil, "iCloud last-writer-wins needs this stamp")
            #expect(!model.isCompleted)
        }
    }

    @Test("Continuing to listen advances the same row instead of adding another")
    func laterTicksUpdateTheSameRow() throws {
        let container = try makeContainer()
        try withCoordinator(container) { coordinator, context in
            coordinator.savePlaybackPosition(update: update(position: 42, duration: 1800))
            coordinator.savePlaybackPosition(update: update(position: 300, duration: 1800))

            let all = try context.fetch(FetchDescriptor<EpisodeDownloadModel>())
            #expect(all.count == 1)
            #expect(all.first?.lastPlaybackPosition == 300)
        }
    }

    @Test("Progress on one episode never leaks into another episode of the same show")
    func progressIsPerEpisode() throws {
        let container = try makeContainer()
        try withCoordinator(container) { coordinator, context in
            coordinator.savePlaybackPosition(update: update(position: 100, duration: 1800, episode: "Episode 1"))
            coordinator.savePlaybackPosition(update: update(position: 700, duration: 1800, episode: "Episode 2"))

            #expect(fetchEpisode(context, episode: "Episode 1")?.lastPlaybackPosition == 100)
            #expect(fetchEpisode(context, episode: "Episode 2")?.lastPlaybackPosition == 700)
        }
    }

    // MARK: - Resuming

    @Test("Resuming an episode starts from the saved position")
    func resumeReturnsSavedPosition() throws {
        let container = try makeContainer()
        try withCoordinator(container) { coordinator, _ in
            coordinator.savePlaybackPosition(update: update(position: 655, duration: 1800))

            let resume = PlaybackStateCoordinator.savedPlaybackPosition(
                podcastTitle: "Daily Tech", episodeTitle: "Episode 1"
            )
            #expect(resume == 655)
        }
    }

    @Test("An unknown episode resumes from zero")
    func unknownEpisodeResumesFromZero() throws {
        let container = try makeContainer()
        try withCoordinator(container) { _, _ in
            let resume = PlaybackStateCoordinator.savedPlaybackPosition(
                podcastTitle: "Daily Tech", episodeTitle: "Never Opened"
            )
            #expect(resume == 0)
        }
    }

    @Test("A finished episode restarts from the beginning rather than the end")
    func completedEpisodeResumesFromZero() throws {
        let container = try makeContainer()
        try withCoordinator(container) { coordinator, context in
            // 5 seconds from the end — inside the completion window.
            coordinator.savePlaybackPosition(update: update(position: 1795, duration: 1800))
            #expect(fetchEpisode(context)?.isCompleted == true)

            let resume = PlaybackStateCoordinator.savedPlaybackPosition(
                podcastTitle: "Daily Tech", episodeTitle: "Episode 1"
            )
            #expect(resume == 0, "replaying a finished episode must not drop the user at the credits")
        }
    }

    // MARK: - Finishing and replaying

    @Test("Reaching the last 30 seconds marks the episode played and counts the play")
    func reachingTheEndCompletesTheEpisode() throws {
        let container = try makeContainer()
        try withCoordinator(container) { coordinator, context in
            coordinator.savePlaybackPosition(update: update(position: 900, duration: 1800))
            #expect(fetchEpisode(context)?.isCompleted == false)
            #expect(fetchEpisode(context)?.playCount == 0)

            coordinator.savePlaybackPosition(update: update(position: 1771, duration: 1800))

            let model = try #require(fetchEpisode(context))
            #expect(model.isCompleted)
            #expect(model.playCount == 1)
            #expect(model.lastPlayedDate != nil)
        }
    }

    @Test("Stopping just outside the completion window leaves the episode unplayed")
    func nearTheEndButNotCompleted() throws {
        let container = try makeContainer()
        try withCoordinator(container) { coordinator, context in
            coordinator.savePlaybackPosition(update: update(position: 1769, duration: 1800))
            #expect(fetchEpisode(context)?.isCompleted == false, "31s left is still in progress")
        }
    }

    @Test("Replaying a finished episode clears the played flag once past the 90% mark")
    func replayResetsCompletion() throws {
        let container = try makeContainer()
        try withCoordinator(container) { coordinator, context in
            coordinator.savePlaybackPosition(update: update(position: 1790, duration: 1800))
            #expect(fetchEpisode(context)?.isCompleted == true)

            // Restarting from the top: below 90%, so the played flag drops and
            // fresh progress tracking begins.
            coordinator.savePlaybackPosition(update: update(position: 30, duration: 1800))

            let model = try #require(fetchEpisode(context))
            #expect(!model.isCompleted)
            #expect(model.lastPlaybackPosition == 30)
            #expect(model.playCount == 1, "the earlier completed listen still counts")
        }
    }

    @Test("Scrubbing back inside the last 10% keeps the episode marked played")
    func lateScrubKeepsCompletion() throws {
        let container = try makeContainer()
        try withCoordinator(container) { coordinator, context in
            coordinator.savePlaybackPosition(update: update(position: 1790, duration: 1800))
            // 95% — still past the replay threshold, so it stays played.
            coordinator.savePlaybackPosition(update: update(position: 1710, duration: 1800))
            #expect(fetchEpisode(context)?.isCompleted == true)
        }
    }

    // MARK: - What the Library shows

    @Test("A started episode reports progress to the Library row")
    func libraryRowShowsProgress() throws {
        let container = try makeContainer()
        try withCoordinator(container) { coordinator, context in
            coordinator.savePlaybackPosition(update: update(position: 450, duration: 1800))
            let model = try #require(fetchEpisode(context))

            let episode = LibraryEpisode(
                id: model.id,
                podcastTitle: model.podcastTitle,
                imageURL: nil,
                language: "en",
                episodeInfo: PodcastEpisodeInfo(title: model.episodeTitle, audioURL: model.audioURL),
                isStarred: model.isStarred,
                isDownloaded: false,
                isCompleted: model.isCompleted,
                lastPlaybackPosition: model.lastPlaybackPosition,
                savedDuration: model.duration
            )

            #expect(episode.hasProgress, "the Library shows a progress bar only when this is true")
            #expect(abs(episode.progress - 0.25) < 0.0001)
            #expect(abs(model.progress - 0.25) < 0.0001)
            #expect(model.remainingTimeString == "22m 30s left")
        }
    }

    @Test("A finished episode shows as played, not as partially listened")
    func libraryRowHidesProgressWhenCompleted() throws {
        let episode = LibraryEpisode(
            id: "k", podcastTitle: "Daily Tech", imageURL: nil, language: "en",
            episodeInfo: PodcastEpisodeInfo(title: "Episode 1", audioURL: "https://example.com/1.mp3"),
            isStarred: false, isDownloaded: false, isCompleted: true,
            lastPlaybackPosition: 1795, savedDuration: 1800
        )
        #expect(!episode.hasProgress, "played episodes show a checkmark, not a half-full bar")
    }

    @Test("Library progress falls back to RSS duration until the player measures one")
    func libraryProgressUsesRSSDurationFallback() throws {
        let episode = LibraryEpisode(
            id: "k", podcastTitle: "Daily Tech", imageURL: nil, language: "en",
            episodeInfo: PodcastEpisodeInfo(title: "Episode 1", audioURL: "u", duration: 1000),
            isStarred: false, isDownloaded: false, isCompleted: false,
            lastPlaybackPosition: 250, savedDuration: 0
        )
        #expect(abs(episode.progress - 0.25) < 0.0001)

        // Once AVPlayer measures the real length it wins over the RSS number,
        // which is frequently wrong.
        let measured = LibraryEpisode(
            id: "k", podcastTitle: "Daily Tech", imageURL: nil, language: "en",
            episodeInfo: PodcastEpisodeInfo(title: "Episode 1", audioURL: "u", duration: 1000),
            isStarred: false, isDownloaded: false, isCompleted: false,
            lastPlaybackPosition: 250, savedDuration: 500
        )
        #expect(abs(measured.progress - 0.5) < 0.0001)
    }

    @Test("An episode with no known duration reports no progress instead of dividing by zero")
    func unknownDurationReportsNoProgress() throws {
        let episode = LibraryEpisode(
            id: "k", podcastTitle: "Daily Tech", imageURL: nil, language: "en",
            episodeInfo: PodcastEpisodeInfo(title: "Episode 1", audioURL: "u"),
            isStarred: false, isDownloaded: false, isCompleted: false,
            lastPlaybackPosition: 250, savedDuration: 0
        )
        #expect(episode.progress == 0)
        #expect(episode.hasProgress, "position alone is still enough to call it started")
    }

    // MARK: - What Up Next shows

    private func libraryEpisode(
        title: String,
        position: TimeInterval,
        duration: TimeInterval,
        isCompleted: Bool = false
    ) -> LibraryEpisode {
        LibraryEpisode(
            id: EpisodeKeyUtils.makeKey(podcastTitle: "Daily Tech", episodeTitle: title),
            podcastTitle: "Daily Tech",
            imageURL: nil,
            language: "en",
            // No pubDate: keeps freshness/new-episode bonuses out of the way so
            // the assertions are about in-progress detection only.
            episodeInfo: PodcastEpisodeInfo(title: title, audioURL: "https://example.com/\(title).mp3"),
            isStarred: false,
            isDownloaded: false,
            isCompleted: isCompleted,
            lastPlaybackPosition: position,
            savedDuration: duration
        )
    }

    @Test("A started episode is surfaced in Up Next with a percent-done badge")
    func upNextSurfacesStartedEpisode() {
        let started = EpisodeInput(
            episode: libraryEpisode(title: "Started", position: 300, duration: 1800),
            downloadModel: nil,
            podcastTotalPlayCount: 0,
            podcastMostRecentPlayDate: nil
        )
        let untouched = EpisodeInput(
            episode: libraryEpisode(title: "Untouched", position: 0, duration: 1800),
            downloadModel: nil,
            podcastTotalPlayCount: 0,
            podcastMostRecentPlayDate: nil
        )

        let ranked = UpNextSuggestionEngine().score(inputs: [untouched, started], now: .now)

        #expect(ranked.first?.episode.episodeInfo.title == "Started", "resume-where-you-left-off outranks a cold episode")
        #expect(ranked.first?.reason == .inProgress(percentComplete: 16))
        #expect(ranked.first?.reason.label == "16% done")
        #expect(ranked.last?.reason != .inProgress(percentComplete: 0))
    }

    private func isInProgress(_ reason: SuggestionReason?) -> Bool {
        if case .some(.inProgress) = reason { return true }
        return false
    }

    @Test("A few seconds of listening is not enough to count as started")
    func upNextIgnoresAccidentalTaps() {
        let barelyTouched = EpisodeInput(
            episode: libraryEpisode(title: "Tapped", position: 10, duration: 1800),
            downloadModel: nil,
            podcastTotalPlayCount: 0,
            podcastMostRecentPlayDate: nil
        )
        let ranked = UpNextSuggestionEngine().score(inputs: [barelyTouched], now: .now)
        #expect(
            !isInProgress(ranked.first?.reason),
            "10s is below the \(UpNextSuggestionEngine.inProgressMinSeconds)s gate"
        )
    }

    @Test("A finished episode stops being offered as in-progress")
    func upNextDropsCompletedEpisodes() {
        let finished = EpisodeInput(
            episode: libraryEpisode(title: "Done", position: 1795, duration: 1800, isCompleted: true),
            downloadModel: nil,
            podcastTotalPlayCount: 0,
            podcastMostRecentPlayDate: nil
        )
        let ranked = UpNextSuggestionEngine().score(inputs: [finished], now: .now)
        #expect(!isInProgress(ranked.first?.reason), "a completed episode must not be labelled in-progress")
        #expect((ranked.first?.score ?? 0) < UpNextSuggestionEngine.bonusInProgressBase)
    }

    // MARK: - Mark as played sticks

    @Test("Marking played mid-listen is not undone by the position write that follows")
    func markPlayedSurvivesTrailingPositionWrite() throws {
        let container = try makeContainer()
        try withCoordinator(container) { coordinator, context in
            // Listening, well short of the end.
            coordinator.savePlaybackPosition(update: update(position: 600, duration: 1800))
            #expect(fetchEpisode(context)?.isCompleted == false)

            // Pausing force-writes the live position. That write has to land
            // *before* the played flag is set — which is what the pause-first
            // ordering in every togglePlayed call site guarantees.
            coordinator.savePlaybackPosition(update: update(position: 600, duration: 1800))

            let model = try #require(fetchEpisode(context))
            model.setCompleted(true)
            model.lastPlaybackPosition = 0
            try context.save()

            // No further position writes arrive, because playback was stopped.
            #expect(fetchEpisode(context)?.isCompleted == true, "the mark must stick")
            #expect(fetchEpisode(context)?.lastPlaybackPosition == 0, "and it restarts next time")
        }
    }

    @Test("A position write arriving after the mark still undoes it — hence pause-first")
    func markPlayedIsUndoneByALaterPositionWrite() throws {
        let container = try makeContainer()
        try withCoordinator(container) { coordinator, context in
            coordinator.savePlaybackPosition(update: update(position: 600, duration: 1800))
            let model = try #require(fetchEpisode(context))
            model.setCompleted(true)
            model.lastPlaybackPosition = 0
            try context.save()

            // This is the bug the pause-first ordering exists to prevent: a
            // still-playing episode ticks its position in after the mark, and
            // the replay heuristic clears the flag. Pinned so nobody "fixes"
            // the ordering away without noticing what it was protecting.
            coordinator.savePlaybackPosition(update: update(position: 601, duration: 1800))
            #expect(
                fetchEpisode(context)?.isCompleted == false,
                "a live position write below 90% still reads as a replay"
            )
        }
    }

    // MARK: - The queue leads Up Next

    @Test("A queued episode outranks every scored suggestion and is listed once")
    func upNextPutsTheQueueFirst() {
        // "Queued" is also the strongest scoring candidate here (in-progress),
        // so if precedence were left to the engine the assertion would pass for
        // the wrong reason. Rank it last by score and queue it anyway.
        let cold = libraryEpisode(title: "Cold", position: 0, duration: 1800)
        let started = libraryEpisode(title: "Started", position: 300, duration: 1800)
        let scored = [started, cold]

        let ordered = UpNextSuggestionEngine.merge(queued: [cold], scored: scored)

        #expect(ordered.first?.episodeInfo.title == "Cold", "what the user queued outranks what the engine picked")
        #expect(ordered.count == 2, "an episode that is both queued and scored is listed once")
        #expect(ordered.map(\.episodeInfo.title) == ["Cold", "Started"])
    }

    @Test("Queue order is preserved ahead of the suggestions")
    func upNextKeepsQueueOrder() {
        let first = libraryEpisode(title: "First", position: 0, duration: 1800)
        let second = libraryEpisode(title: "Second", position: 0, duration: 1800)
        let suggestion = libraryEpisode(title: "Suggested", position: 600, duration: 1800)

        let ordered = UpNextSuggestionEngine.merge(queued: [first, second], scored: [suggestion])

        #expect(ordered.map(\.episodeInfo.title) == ["First", "Second", "Suggested"])
    }

    @Test("An empty queue leaves the scored order untouched")
    func upNextWithEmptyQueueIsUnchanged() {
        let a = libraryEpisode(title: "A", position: 300, duration: 1800)
        let b = libraryEpisode(title: "B", position: 0, duration: 1800)

        let ordered = UpNextSuggestionEngine.merge(queued: [], scored: [a, b])

        #expect(ordered.map(\.episodeInfo.title) == ["A", "B"])
    }

    @Test("The In Queue badge reads as explicit intent")
    func inQueueReasonLabel() {
        #expect(SuggestionReason.inQueue(position: 1).label == "In Queue")
    }

    // MARK: - Marking played from the Library

    @Test("Marking an episode played from the Library clears its progress")
    func markPlayedFromLibraryResetsProgress() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let model = EpisodeDownloadModel(
            episodeTitle: "Episode 1", podcastTitle: "Daily Tech",
            audioURL: "https://example.com/1.mp3",
            lastPlaybackPosition: 450, duration: 1800
        )
        context.insert(model)
        try context.save()

        var models = LibraryEpisodeActions.batchFetchEpisodeModels(from: context)
        #expect(models[model.id] != nil, "batch fetch feeds every Library row")

        let episode = libraryEpisode(title: "Episode 1", position: 450, duration: 1800)
        LibraryEpisodeActions.togglePlayed(episode, episodeModels: &models, context: context)

        #expect(model.isCompleted)
        #expect(model.lastPlaybackPosition == 0, "played episodes must not keep a resume point")
        #expect(model.lastPlayedDate != nil)

        // Toggling back leaves it unplayed and at the start.
        LibraryEpisodeActions.togglePlayed(episode, episodeModels: &models, context: context)
        #expect(!model.isCompleted)
    }

    @Test("Saving an episode the Library has never stored creates the row on demand")
    func starringCreatesRowOnDemand() throws {
        let container = try makeContainer()
        let context = container.mainContext
        var models: [String: EpisodeDownloadModel] = [:]

        let episode = LibraryEpisode(
            id: EpisodeKeyUtils.makeKey(podcastTitle: "Daily Tech", episodeTitle: "Fresh"),
            podcastTitle: "Daily Tech", imageURL: "https://example.com/art.jpg", language: "en",
            episodeInfo: PodcastEpisodeInfo(title: "Fresh", audioURL: "https://example.com/fresh.mp3"),
            isStarred: false, isDownloaded: false, isCompleted: false,
            lastPlaybackPosition: 0, savedDuration: 0
        )

        LibraryEpisodeActions.toggleStar(episode, episodeModels: &models, context: context, createIfMissing: true)

        let stored = try #require(fetchEpisode(context, episode: "Fresh"))
        #expect(stored.isStarred)
        #expect(stored.audioURL == "https://example.com/fresh.mp3")
        #expect(models[episode.id] != nil, "the caller's cache is updated so the row flips immediately")
    }
}
