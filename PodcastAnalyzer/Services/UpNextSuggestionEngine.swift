//
//  UpNextSuggestionEngine.swift
//  PodcastAnalyzer
//
//  Local-first scoring engine for the Up Next feed.
//  No network calls, no actor isolation — pure value-type logic, fully unit-testable.
//

import Foundation

// MARK: - SuggestionReason

/// Why an episode was surfaced in Up Next.
/// The highest-priority applicable reason is shown as a badge on the card.
enum SuggestionReason: Equatable {
    case inProgress(percentComplete: Int)  // "32% done"
    case starred                            // "Saved"
    case downloaded                         // "Downloaded"
    case listenOften                        // "You listen often"
    case newEpisode                         // "New episode"
    case recentPodcast                      // "From a show you follow"
    case none

    var label: String {
        switch self {
        case .inProgress(let pct): return "\(pct)% done"
        case .starred:             return "Saved"
        case .downloaded:          return "Downloaded"
        case .listenOften:         return "You listen often"
        case .newEpisode:          return "New episode"
        case .recentPodcast:       return "From a show you follow"
        case .none:                return ""
        }
    }

    var systemImage: String {
        switch self {
        case .inProgress:    return "play.circle.fill"
        case .starred:       return "star.fill"
        case .downloaded:    return "arrow.down.circle.fill"
        case .listenOften:   return "headphones"
        case .newEpisode:    return "sparkle"
        case .recentPodcast: return "clock"
        case .none:          return ""
        }
    }
}

// MARK: - EpisodeInput

/// All signals needed to score one episode candidate.
/// Assembled once in HomeViewModel from the already-fetched `modelsByKey` dict.
struct EpisodeInput {
    let episode: LibraryEpisode
    let downloadModel: EpisodeDownloadModel?

    // Per-podcast aggregates (computed once per podcast, shared across all its episodes)
    let podcastTotalPlayCount: Int       // sum of playCount across all stored eps for this podcast
    let podcastMostRecentPlayDate: Date? // max(lastPlayedDate) across all stored eps for this podcast
}

// MARK: - ScoredEpisode

struct ScoredEpisode: Identifiable {
    let episode: LibraryEpisode
    let downloadModel: EpisodeDownloadModel?
    let score: Double
    let reason: SuggestionReason
    let progressRatio: Double  // 0 if not in-progress; drives "X% done" label

    var id: String { episode.id }
}

// MARK: - UpNextSuggestionEngine

struct UpNextSuggestionEngine {

    // MARK: Tuning constants

    /// Episodes with progressRatio above this are treated as in-progress.
    static let inProgressMinRatio: Double = 0.05

    /// Minimum absolute position (seconds) to count as in-progress when duration is unknown.
    static let inProgressMinSeconds: Double = 60

    /// Freshness factor decays to 0 at this many days.
    static let freshnessHalfLifeDays: Double = 14

    /// Podcast engagement score saturates at this many total plays.
    static let engagementSaturationPlays: Int = 20

    /// Recency window for "last played this podcast" signal.
    static let podcastRecencyWindowDays: Double = 7

    /// Episodes older than this with no plays receive a small penalty.
    static let stalePenaltyThresholdDays: Double = 60

    /// Floor multiplier for freshness when podcast engagement is zero.
    static let freshnessEngagementFloor: Double = 0.3

    /// Bonus for new episodes (within newEpisodeThresholdDays) from an engaged podcast.
    static let bonusNewEpisodeEngaged: Double = 20

    /// Age threshold (days) for "new episode" engaged-podcast bonus.
    static let newEpisodeThresholdDays: Double = 3

    /// Bonus for in-progress episodes that were recently played.
    static let bonusInProgressRecency: Double = 15

    /// Window (days) over which in-progress recency bonus decays to zero.
    static let inProgressRecencyWindowDays: Double = 7

    // MARK: Score weights

    static let bonusInProgressBase: Double = 80    // always beats non-in-progress
    static let bonusInProgressProgress: Double = 20 // up to +20 for how far along
    static let weightFreshness: Double = 30
    static let weightEngagement: Double = 30
    static let bonusDownloaded: Double = 20
    static let bonusStarred: Double = 15
    static let weightPodcastRecency: Double = 10
    static let penaltyStale: Double = -5

    // MARK: - Public API

    /// Scores and ranks episode candidates.
    /// Returns descending by score, capped at `limit`.
    func score(
        inputs: [EpisodeInput],
        limit: Int = 25,
        now: Date = .now
    ) -> [ScoredEpisode] {
        inputs
            .map { score(input: $0, now: now) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Private: per-episode scoring

    private func score(input: EpisodeInput, now: Date) -> ScoredEpisode {
        let model = input.downloadModel
        let episodeInfo = input.episode.episodeInfo

        // Effective duration: prefer measured AVPlayer duration, fallback to RSS metadata
        let effectiveDuration: Double = {
            let saved = input.episode.savedDuration
            if saved > 0 { return saved }
            if let rss = episodeInfo.duration { return Double(rss) }
            return 0
        }()

        let position = input.episode.lastPlaybackPosition

        // Progress ratio (0.0 – 1.0)
        let progressRatio: Double = effectiveDuration > 0
            ? min(position / effectiveDuration, 1.0)
            : 0

        // In-progress detection: ratio threshold OR absolute position when duration unknown
        let isInProgress: Bool = {
            if input.episode.isCompleted { return false }
            if effectiveDuration > 0 {
                return progressRatio > Self.inProgressMinRatio
            } else {
                return position > Self.inProgressMinSeconds
            }
        }()

        var s: Double = 0

        // ── In-progress bonus (always beats non-in-progress) ──────────────
        if isInProgress {
            s += Self.bonusInProgressBase
            s += progressRatio * Self.bonusInProgressProgress
        }

        // ── In-progress recency bonus (recently-played episodes rank higher) ──
        if isInProgress, let lastPlay = model?.lastPlayedDate {
            let daysSince = now.timeIntervalSince(lastPlay) / 86_400
            let recencyFactor = max(0, 1.0 - daysSince / Self.inProgressRecencyWindowDays)
            s += recencyFactor * Self.bonusInProgressRecency
        }

        // ── Podcast engagement (compute early — used by freshness below) ──────
        let engagementFactor = min(
            Double(input.podcastTotalPlayCount) / Double(Self.engagementSaturationPlays),
            1.0
        )
        s += engagementFactor * Self.weightEngagement

        // ── Freshness (gated by engagement to reduce noise from cold podcasts) ─
        if let pubDate = episodeInfo.pubDate {
            let ageInDays = now.timeIntervalSince(pubDate) / 86_400
            let clamped = min(max(ageInDays, 0), 90)
            let rawFreshness = max(0, 1.0 - clamped / Self.freshnessHalfLifeDays)
            let scaledFreshness = rawFreshness * (Self.freshnessEngagementFloor + (1 - Self.freshnessEngagementFloor) * engagementFactor)
            s += scaledFreshness * Self.weightFreshness
        }

        // ── New episode bonus for engaged podcasts ────────────────────────────
        if let pubDate = episodeInfo.pubDate {
            let ageInDays = now.timeIntervalSince(pubDate) / 86_400
            if ageInDays <= Self.newEpisodeThresholdDays {
                s += engagementFactor * Self.bonusNewEpisodeEngaged
            }
        }

        // ── Downloaded ───────────────────────────────────────────────────
        if input.episode.isDownloaded {
            s += Self.bonusDownloaded
        }

        // ── Starred ──────────────────────────────────────────────────────
        if input.episode.isStarred {
            s += Self.bonusStarred
        }

        // ── Recent podcast activity ───────────────────────────────────────
        if let lastPlay = input.podcastMostRecentPlayDate {
            let daysSince = now.timeIntervalSince(lastPlay) / 86_400
            let recency = max(0, 1.0 - daysSince / Self.podcastRecencyWindowDays)
            s += recency * Self.weightPodcastRecency
        }

        // ── Stale penalty ─────────────────────────────────────────────────
        if let pubDate = episodeInfo.pubDate,
           model?.lastPlayedDate == nil {
            let ageInDays = now.timeIntervalSince(pubDate) / 86_400
            if ageInDays > Self.stalePenaltyThresholdDays {
                s += Self.penaltyStale
            }
        }

        // ── Reason label ─────────────────────────────────────────────────
        let reason = primaryReason(
            isInProgress: isInProgress,
            progressRatio: progressRatio,
            isStarred: input.episode.isStarred,
            isDownloaded: input.episode.isDownloaded,
            podcastTotalPlayCount: input.podcastTotalPlayCount,
            pubDate: episodeInfo.pubDate,
            podcastMostRecentPlayDate: input.podcastMostRecentPlayDate,
            now: now
        )

        return ScoredEpisode(
            episode: input.episode,
            downloadModel: model,
            score: s,
            reason: reason,
            progressRatio: progressRatio
        )
    }

    // MARK: - Reason assignment

    private func primaryReason(
        isInProgress: Bool,
        progressRatio: Double,
        isStarred: Bool,
        isDownloaded: Bool,
        podcastTotalPlayCount: Int,
        pubDate: Date?,
        podcastMostRecentPlayDate: Date?,
        now: Date
    ) -> SuggestionReason {
        // Priority order: in-progress > starred > downloaded > listenOften > newEpisode > recentPodcast
        if isInProgress {
            return .inProgress(percentComplete: Int(progressRatio * 100))
        }
        if isStarred {
            return .starred
        }
        if isDownloaded {
            return .downloaded
        }
        if podcastTotalPlayCount >= 5 {
            return .listenOften
        }
        if let pub = pubDate {
            let ageInDays = now.timeIntervalSince(pub) / 86_400
            if ageInDays <= 3 {
                return .newEpisode
            }
        }
        if podcastMostRecentPlayDate != nil {
            return .recentPodcast
        }
        return .none
    }
}
