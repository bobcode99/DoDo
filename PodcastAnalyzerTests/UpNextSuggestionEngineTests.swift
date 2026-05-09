//
//  UpNextSuggestionEngineTests.swift
//  PodcastAnalyzerTests
//
//  Pure-function tests for the Up Next scoring engine.
//  Exercises the Apple-Podcasts-style retune: 15 s in-progress threshold,
//  fresh-from-engaged outranks generic in-progress, and lower-tier subscribed bonus.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@MainActor
struct UpNextSuggestionEngineTests {

  // MARK: - Helpers

  private func makeLibraryEpisode(
    id: String,
    title: String = "Ep",
    pubDate: Date? = nil,
    audioURL: String? = "https://example.com/a.mp3",
    duration: Int? = nil,
    lastPlaybackPosition: TimeInterval = 0,
    savedDuration: TimeInterval = 0,
    isCompleted: Bool = false,
    isStarred: Bool = false,
    isDownloaded: Bool = false
  ) -> LibraryEpisode {
    let info = PodcastEpisodeInfo(
      title: title,
      pubDate: pubDate,
      audioURL: audioURL,
      duration: duration
    )
    return LibraryEpisode(
      id: id,
      podcastTitle: "Show",
      imageURL: nil,
      language: "en",
      episodeInfo: info,
      isStarred: isStarred,
      isDownloaded: isDownloaded,
      isCompleted: isCompleted,
      lastPlaybackPosition: lastPlaybackPosition,
      savedDuration: savedDuration
    )
  }

  private func makeInput(
    episode: LibraryEpisode,
    podcastTotalPlayCount: Int = 0,
    podcastMostRecentPlayDate: Date? = nil
  ) -> EpisodeInput {
    EpisodeInput(
      episode: episode,
      downloadModel: nil,
      podcastTotalPlayCount: podcastTotalPlayCount,
      podcastMostRecentPlayDate: podcastMostRecentPlayDate
    )
  }

  // MARK: - In-progress threshold

  @Test func inProgress_at16Seconds_isInProgress() throws {
    let episode = makeLibraryEpisode(id: "a", lastPlaybackPosition: 16)
    let scored = UpNextSuggestionEngine().score(inputs: [makeInput(episode: episode)])
    let row = try #require(scored.first)
    if case .inProgress = row.reason { } else {
      Issue.record("Expected .inProgress reason for 16 s playback")
    }
  }

  @Test func inProgress_at14Seconds_notInProgress() throws {
    let episode = makeLibraryEpisode(id: "a", lastPlaybackPosition: 14)
    let scored = UpNextSuggestionEngine().score(inputs: [makeInput(episode: episode)])
    let row = try #require(scored.first)
    if case .inProgress = row.reason {
      Issue.record("Did not expect .inProgress reason for 14 s playback")
    }
  }

  @Test func inProgress_noRatioGate_lowPercentageStillCounts() throws {
    // 20 s into a 1000 s episode (2 %) — old logic with 5 % ratio gate would exclude.
    let episode = makeLibraryEpisode(
      id: "a",
      duration: 1000,
      lastPlaybackPosition: 20,
      savedDuration: 1000
    )
    let scored = UpNextSuggestionEngine().score(inputs: [makeInput(episode: episode)])
    let row = try #require(scored.first)
    if case .inProgress = row.reason { } else {
      Issue.record("Expected .inProgress reason regardless of ratio")
    }
  }

  // MARK: - Fresh-from-engaged

  @Test func freshFromEngaged_outranksInProgress() throws {
    let now = Date()
    let oneDayAgo = now.addingTimeInterval(-86_400)

    // Engaged podcast (10 prior plays), brand-new episode, no progress.
    let fresh = makeLibraryEpisode(
      id: "fresh",
      pubDate: oneDayAgo,
      duration: 1800
    )

    // Same engaged podcast, 50 % in-progress, played 2 hours ago.
    let inProgress = makeLibraryEpisode(
      id: "inProgress",
      pubDate: now.addingTimeInterval(-30 * 86_400),
      duration: 1800,
      lastPlaybackPosition: 900,
      savedDuration: 1800
    )

    let scored = UpNextSuggestionEngine().score(
      inputs: [
        makeInput(episode: fresh, podcastTotalPlayCount: 10,
                  podcastMostRecentPlayDate: now.addingTimeInterval(-7_200)),
        makeInput(episode: inProgress, podcastTotalPlayCount: 10,
                  podcastMostRecentPlayDate: now.addingTimeInterval(-7_200)),
      ],
      now: now
    )

    let freshRow = try #require(scored.first { $0.episode.id == "fresh" })
    let inProgressRow = try #require(scored.first { $0.episode.id == "inProgress" })
    #expect(freshRow.score > inProgressRow.score,
            "Fresh-from-engaged (\(freshRow.score)) should outrank in-progress (\(inProgressRow.score))")
    #expect(freshRow.reason == .newEpisode)
  }

  @Test func freshSubscribed_fallback_belowEngagedThreshold() throws {
    // Podcast has zero prior plays, episode is 2 days old → only the lower-tier bonus applies.
    let now = Date()
    let twoDaysAgo = now.addingTimeInterval(-2 * 86_400)
    let episode = makeLibraryEpisode(id: "a", pubDate: twoDaysAgo, duration: 1800)
    let scored = UpNextSuggestionEngine().score(
      inputs: [makeInput(episode: episode, podcastTotalPlayCount: 0)],
      now: now
    )
    let row = try #require(scored.first)

    // Compare to a baseline with the same episode but pub-date older than the
    // freshSubscribed window — its score is the score WITHOUT the fresh-subscribed bonus.
    let stale = makeLibraryEpisode(
      id: "stale",
      pubDate: now.addingTimeInterval(-30 * 86_400),
      duration: 1800
    )
    let baseline = UpNextSuggestionEngine().score(
      inputs: [makeInput(episode: stale, podcastTotalPlayCount: 0)],
      now: now
    ).first!.score

    let delta = row.score - baseline
    #expect(delta >= UpNextSuggestionEngine.bonusFreshSubscribed - 1,
            "Expected ~bonusFreshSubscribed lift, got \(delta)")
    #expect(delta < UpNextSuggestionEngine.bonusFreshFromEngaged - 1,
            "Should NOT receive the engaged bonus; got delta \(delta)")
  }

  @Test func freshFromEngaged_skippedIfInProgress() throws {
    // An engaged + recent episode that is also in-progress should NOT double-count
    // the fresh-from-engaged bonus (gated on !isInProgress).
    let now = Date()
    let oneDayAgo = now.addingTimeInterval(-86_400)
    let episode = makeLibraryEpisode(
      id: "a",
      pubDate: oneDayAgo,
      duration: 1800,
      lastPlaybackPosition: 60,    // > 15s threshold
      savedDuration: 1800
    )
    let scored = UpNextSuggestionEngine().score(
      inputs: [makeInput(episode: episode, podcastTotalPlayCount: 20)],
      now: now
    )
    let row = try #require(scored.first)
    // Reason resolves to .inProgress because the engaged-fresh branch in primaryReason
    // is also gated on !isInProgress.
    if case .inProgress = row.reason { } else {
      Issue.record("Expected .inProgress when engaged-fresh episode is also being played")
    }
    // Sanity: score stays below the fresh-from-engaged ceiling.
    #expect(row.score < UpNextSuggestionEngine.bonusFreshFromEngaged + 50)
  }

  // MARK: - Completed exclusion

  @Test func completedEpisode_isNotInProgress() throws {
    let episode = makeLibraryEpisode(
      id: "a",
      lastPlaybackPosition: 600,
      savedDuration: 600,
      isCompleted: true
    )
    let scored = UpNextSuggestionEngine().score(inputs: [makeInput(episode: episode)])
    let row = try #require(scored.first)
    if case .inProgress = row.reason {
      Issue.record("Completed episode should not be flagged as in-progress")
    }
  }
}
