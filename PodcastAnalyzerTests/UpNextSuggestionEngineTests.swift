//
//  UpNextSuggestionEngineTests.swift
//  PodcastAnalyzerTests
//
//  Up Next is the first thing on Home, so its ordering *is* the product for most
//  sessions. The engine is pure by design, and these tests pin the ordering
//  rules rather than the arithmetic: a half-finished episode comes back before
//  anything untouched, a new episode from a show you actually listen to beats
//  that, and what you explicitly queued beats everything the engine inferred.
//
//  Scores are compared, never asserted equal to a literal — the weights are
//  meant to be tuned, the resulting order is not.
//

import Foundation
import SwiftData
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Up Next suggestion ordering")
struct UpNextSuggestionEngineTests {

    private let engine = UpNextSuggestionEngine()
    private let now = Date(timeIntervalSince1970: 1_770_000_000)

    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    private func episode(
        _ id: String,
        podcast: String = "The Show",
        pubDate: Date? = nil,
        duration: Int? = 3600,
        savedDuration: TimeInterval = 3600,
        position: TimeInterval = 0,
        isCompleted: Bool = false,
        isStarred: Bool = false,
        isDownloaded: Bool = false
    ) -> LibraryEpisode {
        LibraryEpisode(
            id: id,
            podcastTitle: podcast,
            imageURL: nil,
            language: "en",
            episodeInfo: PodcastEpisodeInfo(
                title: id,
                pubDate: pubDate,
                audioURL: "https://example.com/\(id).mp3",
                duration: duration
            ),
            isStarred: isStarred,
            isDownloaded: isDownloaded,
            isCompleted: isCompleted,
            lastPlaybackPosition: position,
            savedDuration: savedDuration
        )
    }

    private func input(
        _ episode: LibraryEpisode,
        model: EpisodeDownloadModel? = nil,
        plays: Int = 0,
        lastPlayedPodcast: Date? = nil
    ) -> EpisodeInput {
        EpisodeInput(
            episode: episode,
            downloadModel: model,
            podcastTotalPlayCount: plays,
            podcastMostRecentPlayDate: lastPlayedPodcast
        )
    }

    private func scored(_ inputs: [EpisodeInput], limit: Int = 25) -> [ScoredEpisode] {
        engine.score(inputs: inputs, limit: limit, now: now)
    }

    private func score(_ input: EpisodeInput) -> Double {
        scored([input])[0].score
    }

    // MARK: - In-progress

    @Test("A half-finished episode outranks an untouched one from the same show")
    func inProgressOutranksUntouched() {
        let ranked = scored([
            input(episode("untouched", pubDate: daysAgo(20))),
            input(episode("halfway", pubDate: daysAgo(20), position: 1800)),
        ])

        #expect(ranked.first?.episode.id == "halfway")
    }

    @Test("A few seconds of accidental playback is not 'in progress'")
    func shortPlaybackIsNotProgress() {
        // Below the 15-second gate: a mis-tap must not pin an episode to Up Next.
        let brushed = scored([input(episode("brushed", position: 10))])[0]
        #expect(brushed.reason != .inProgress(percentComplete: 0))

        let started = scored([input(episode("started", position: 60))])[0]
        #expect(started.reason == .inProgress(percentComplete: 1))
    }

    @Test("A finished episode is not treated as in progress even with a saved position")
    func completedIsNotInProgress() {
        let done = episode("done", position: 3500, isCompleted: true)
        let ongoing = episode("ongoing", position: 3500)

        #expect(score(input(done)) < score(input(ongoing)))
        #expect(scored([input(done)])[0].reason != .inProgress(percentComplete: 97))
    }

    @Test("Progress is reported from the measured duration, not the feed's claim")
    func progressPrefersMeasuredDuration() {
        // The feed claims one hour; AVPlayer measured half that.
        let episode = episode("mislabelled", duration: 3600, savedDuration: 1800, position: 900)
        #expect(scored([input(episode)])[0].progressRatio == 0.5)
    }

    @Test("Progress falls back to the feed's duration when nothing has been measured")
    func progressFallsBackToFeedDuration() {
        let episode = episode("unmeasured", duration: 3600, savedDuration: 0, position: 900)
        #expect(scored([input(episode)])[0].progressRatio == 0.25)
    }

    @Test("A position beyond the duration clamps to fully played rather than overflowing")
    func progressClampsAtOne() {
        let episode = episode("overrun", savedDuration: 1000, position: 5000)
        #expect(scored([input(episode)])[0].progressRatio == 1.0)
    }

    @Test("An episode of unknown length scores without dividing by zero")
    func unknownDurationIsSafe() {
        let episode = episode("unknown", duration: nil, savedDuration: 0, position: 600)
        let result = scored([input(episode)])[0]

        #expect(result.progressRatio == 0)
        #expect(result.score.isFinite)
    }

    // MARK: - Freshness and engagement

    @Test("A new episode from a show you listen to outranks a generic in-progress episode")
    func freshFromEngagedTopsTheList() {
        let ranked = scored([
            input(episode("halfway", pubDate: daysAgo(30), position: 1800)),
            input(episode("brand-new", pubDate: daysAgo(1)), plays: 10),
        ])

        #expect(ranked.first?.episode.id == "brand-new")
    }

    @Test("A new episode from a show you've barely touched does not top the list")
    func freshFromColdShowDoesNotTop() {
        let ranked = scored([
            input(episode("halfway", pubDate: daysAgo(30), position: 1800)),
            input(episode("brand-new", pubDate: daysAgo(1)), plays: 0),
        ])

        #expect(ranked.first?.episode.id == "halfway")
    }

    @Test("The same episode scores higher for a show with more plays behind it")
    func engagementRaisesScore() {
        let template = episode("ep", pubDate: daysAgo(30))
        #expect(score(input(template, plays: 20)) > score(input(template, plays: 0)))
    }

    @Test("A recent episode outscores an older one, all else equal")
    func freshnessRaisesScore() {
        #expect(score(input(episode("new", pubDate: daysAgo(1)), plays: 3))
                > score(input(episode("old", pubDate: daysAgo(30)), plays: 3)))
    }

    @Test("An episode past the stale threshold is penalised over one just inside it")
    func stalePenaltyApplies() {
        // Both are far past the freshness window, so the only difference left is
        // the stale penalty.
        #expect(score(input(episode("stale", pubDate: daysAgo(61))))
                < score(input(episode("old", pubDate: daysAgo(59)))))
    }

    @Test("An episode with no publication date still scores without crashing")
    func missingPubDateIsSafe() {
        #expect(score(input(episode("undated", pubDate: nil))).isFinite)
    }

    // MARK: - Explicit user signals

    @Test("Downloading an episode raises it")
    func downloadRaisesScore() {
        let base = episode("ep", pubDate: daysAgo(30))
        let downloaded = episode("ep", pubDate: daysAgo(30), isDownloaded: true)
        #expect(score(input(downloaded)) > score(input(base)))
    }

    @Test("Starring an episode raises it")
    func starRaisesScore() {
        let base = episode("ep", pubDate: daysAgo(30))
        let starred = episode("ep", pubDate: daysAgo(30), isStarred: true)
        #expect(score(input(starred)) > score(input(base)))
    }

    @Test("Recent activity on a show lifts its episodes")
    func podcastRecencyRaisesScore() {
        let template = episode("ep", pubDate: daysAgo(30))
        #expect(score(input(template, lastPlayedPodcast: daysAgo(1)))
                > score(input(template, lastPlayedPodcast: daysAgo(30))))
    }

    @Test("An episode played today outranks the same progress from a fortnight ago")
    func inProgressRecencyRaisesScore() throws {
        let schema = Schema([EpisodeDownloadModel.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)

        func model(lastPlayed: Date) -> EpisodeDownloadModel {
            let model = EpisodeDownloadModel(
                episodeTitle: "ep", podcastTitle: "The Show",
                audioURL: "https://example.com/ep.mp3",
                lastPlaybackPosition: 1800, duration: 3600, lastPlayedDate: lastPlayed)
            context.insert(model)
            return model
        }

        let episode = episode("ep", pubDate: daysAgo(30), position: 1800)
        let fresh = input(episode, model: model(lastPlayed: daysAgo(0)))
        let stale = input(episode, model: model(lastPlayed: daysAgo(14)))

        #expect(score(fresh) > score(stale))
    }

    // MARK: - Reasons

    @Test("The badge shows the highest-priority reason that applies")
    func reasonPriority() {
        // Starred and downloaded both apply, but being mid-episode wins.
        let midEpisode = episode("mid", pubDate: daysAgo(30), position: 1800,
                                 isStarred: true, isDownloaded: true)
        #expect(scored([input(midEpisode)])[0].reason == .inProgress(percentComplete: 50))

        // Not started: starred outranks downloaded.
        let saved = episode("saved", pubDate: daysAgo(30), isStarred: true, isDownloaded: true)
        #expect(scored([input(saved)])[0].reason == .starred)

        // Only downloaded.
        let downloaded = episode("dl", pubDate: daysAgo(30), isDownloaded: true)
        #expect(scored([input(downloaded)])[0].reason == .downloaded)

        // Nothing but a history with the show.
        let often = episode("often", pubDate: daysAgo(30))
        #expect(scored([input(often, plays: 8)])[0].reason == .listenOften)
    }

    @Test("A brand-new episode from a show you follow is badged as new, not as in-progress")
    func newEpisodeReasonWinsForFreshEngaged() {
        let fresh = episode("fresh", pubDate: daysAgo(1), isStarred: true)
        #expect(scored([input(fresh, plays: 10)])[0].reason == .newEpisode)
    }

    @Test("An episode with nothing to say about it carries no badge")
    func noReason() {
        let anonymous = episode("anon", pubDate: nil)
        #expect(scored([input(anonymous)])[0].reason == .none)
        #expect(SuggestionReason.none.label.isEmpty)
        #expect(SuggestionReason.none.systemImage.isEmpty)
    }

    @Test("Every badge that is shown has both a label and an icon",
          arguments: [SuggestionReason.inQueue(position: 1),
                      .inProgress(percentComplete: 50), .starred, .downloaded,
                      .listenOften, .newEpisode, .recentPodcast])
    func reasonsAreDisplayable(_ reason: SuggestionReason) {
        #expect(reason.label.isEmpty == false)
        #expect(reason.systemImage.isEmpty == false)
    }

    // MARK: - Ranking mechanics

    @Test("Results come back highest-scoring first")
    func resultsAreSorted() {
        let ranked = scored([
            input(episode("cold", pubDate: daysAgo(80))),
            input(episode("hot", pubDate: daysAgo(1)), plays: 10),
            input(episode("warm", pubDate: daysAgo(30), position: 1800)),
        ])

        #expect(ranked.map(\.score) == ranked.map(\.score).sorted(by: >))
        #expect(ranked.count == 3)
    }

    @Test("The limit truncates from the bottom, keeping the best")
    func limitKeepsTheBest() {
        let inputs = (1...10).map { input(episode("ep\($0)", pubDate: daysAgo(Double($0)))) }
        let ranked = scored(inputs, limit: 3)

        #expect(ranked.count == 3)
        #expect(ranked.map(\.score) == ranked.map(\.score).sorted(by: >))
        #expect(ranked[0].score >= scored(inputs)[3].score)
    }

    @Test("Nothing to rank produces nothing, not a crash")
    func emptyInput() {
        #expect(scored([]).isEmpty)
    }

    // MARK: - Merge with the explicit queue

    @Test("What the user queued comes first, in queue order")
    func queuedComesFirst() {
        let queued = [episode("q1"), episode("q2")]
        let suggested = [episode("s1"), episode("s2")]

        let merged = UpNextSuggestionEngine.merge(queued: queued, scored: suggested)
        #expect(merged.map(\.id) == ["q1", "q2", "s1", "s2"])
    }

    @Test("An episode that is both queued and suggested is listed once, in its queue position")
    func mergeDeduplicates() {
        let shared = episode("shared")
        let merged = UpNextSuggestionEngine.merge(
            queued: [shared, episode("q2")],
            scored: [episode("s1"), shared])

        #expect(merged.map(\.id) == ["shared", "q2", "s1"])
    }

    @Test("Merging with an empty side returns the other side unchanged")
    func mergeWithEmpty() {
        let episodes = [episode("a"), episode("b")]

        #expect(UpNextSuggestionEngine.merge(queued: [], scored: episodes).map(\.id) == ["a", "b"])
        #expect(UpNextSuggestionEngine.merge(queued: episodes, scored: []).map(\.id) == ["a", "b"])
        #expect(UpNextSuggestionEngine.merge(queued: [], scored: []).isEmpty)
    }

    @Test("A duplicate inside the queue itself is collapsed")
    func mergeCollapsesRepeatedQueueEntries() {
        let shared = episode("dupe")
        #expect(UpNextSuggestionEngine.merge(queued: [shared, shared], scored: []).count == 1)
    }
}
