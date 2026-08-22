//
//  ListeningStatsViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for listening statistics - aggregates SwiftData playback history
//

import Foundation
import Observation
import SwiftData
import OSLog

// MARK: - Time Period

enum TimePeriod: String, CaseIterable, Identifiable {
  case oneMonth = "1M"
  case threeMonths = "3M"
  case oneYear = "1Y"
  case allTime = "All"

  var id: String { rawValue }

  var displayName: String { rawValue }

  var cutoffDate: Date? {
    let calendar = Calendar.current
    switch self {
    case .oneMonth:
      return calendar.date(byAdding: .month, value: -1, to: Date())
    case .threeMonths:
      return calendar.date(byAdding: .month, value: -3, to: Date())
    case .oneYear:
      return calendar.date(byAdding: .year, value: -1, to: Date())
    case .allTime:
      return nil
    }
  }
}

// MARK: - Podcast Listening Stat

struct PodcastListeningStat: Identifiable {
  let id = UUID()
  let podcastTitle: String
  let totalListeningTime: TimeInterval
  let playCount: Int
  let imageURL: String?

  var totalHours: Double {
    totalListeningTime / 3600.0
  }
}

// MARK: - Weekly Listening Bucket

struct WeeklyListeningBucket: Identifiable {
  let id = UUID()
  /// The Monday of the week this bucket represents.
  let weekStart: Date
  let hours: Double
}

// MARK: - ViewModel

@MainActor
@Observable
final class ListeningStatsViewModel {
  var selectedTimePeriod: TimePeriod = .allTime
  var totalHoursListened: Double = 0
  var totalEpisodesPlayed: Int = 0
  var topPodcasts: [PodcastListeningStat] = []
  var weeklyBuckets: [WeeklyListeningBucket] = []
  var longestStreakDays: Int = 0
  var isLoading = false

  @ObservationIgnored
  private var modelContext: ModelContext?

  @ObservationIgnored
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "ListeningStatsViewModel")

  func setModelContext(_ context: ModelContext) {
    self.modelContext = context
    loadStats()
  }

  func loadStats() {
    guard let context = modelContext else { return }
    isLoading = true

    let cutoff = selectedTimePeriod.cutoffDate

    // Fetch all EpisodeDownloadModel sorted by lastPlayedDate descending
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      sortBy: [SortDescriptor(\.lastPlayedDate, order: .reverse)]
    )

    do {
      let allModels = try context.fetch(descriptor)

      // Filter: has meaningful playback + within time period
      // "Meaningful" = completed at least once OR listened more than 60 seconds
      let filtered = allModels.filter { model in
        let hasMeaningfulPlay = model.playCount > 0 || model.lastPlaybackPosition > 60
        guard hasMeaningfulPlay else { return false }

        if let cutoff {
          return (model.lastPlayedDate ?? .distantPast) >= cutoff
        }
        return true
      }

      // Total episodes played: distinct episodes with meaningful progress
      totalEpisodesPlayed = filtered.count

      // Total hours listened:
      //   completedTime = episodeDuration × completedPlays
      //   inProgressTime = lastPlaybackPosition (when not currently completed)
      //
      // For old data where isCompleted=true but playCount=0 (before playCount tracking),
      // treat as 1 completed play so legacy history isn't lost.
      var totalSeconds: TimeInterval = 0
      var podcastGroups: [String: (time: TimeInterval, count: Int, imageURL: String?)] = [:]

      for model in filtered {
        let episodeDuration = model.duration > 0 ? model.duration : model.lastPlaybackPosition
        // Backward-compat: episodes completed before playCount tracking have playCount=0
        let completedPlays = model.isCompleted ? max(model.playCount, 1) : model.playCount
        let completedTime = episodeDuration * Double(completedPlays)
        let inProgressTime: TimeInterval = model.isCompleted ? 0 : model.lastPlaybackPosition
        let listeningTime = completedTime + inProgressTime
        totalSeconds += listeningTime

        // Group by podcast title — count distinct episodes (not total plays)
        let title = model.podcastTitle
        let existing = podcastGroups[title] ?? (time: 0, count: 0, imageURL: model.imageURL)
        podcastGroups[title] = (
          time: existing.time + listeningTime,
          count: existing.count + 1,
          imageURL: existing.imageURL ?? model.imageURL
        )
      }

      totalHoursListened = totalSeconds / 3600.0

      // Top 3 podcasts sorted by listening time
      let artworkByPodcast = podcastArtworkByTitle(
        for: podcastGroups.filter { $0.value.imageURL == nil }.keys,
        context: context
      )
      topPodcasts = podcastGroups
        .map {
          PodcastListeningStat(
            podcastTitle: $0.key,
            totalListeningTime: $0.value.time,
            playCount: $0.value.count,
            imageURL: $0.value.imageURL ?? artworkByPodcast[$0.key]
          )
        }
        .sorted { $0.totalListeningTime > $1.totalListeningTime }
        .prefix(3)
        .map { $0 }

      // Weekly buckets — group listening time by calendar week
      weeklyBuckets = buildWeeklyBuckets(from: filtered)

      // Longest consecutive listening streak (days)
      longestStreakDays = computeLongestStreak(from: filtered)

      logger.info("Stats loaded: \(self.totalEpisodesPlayed) episodes, \(String(format: "%.1f", self.totalHoursListened))h, \(self.topPodcasts.count) top podcasts")
    } catch {
      logger.error("Failed to load listening stats: \(error.localizedDescription, privacy: .public)")
    }

    isLoading = false
  }

  // MARK: - Weekly Buckets

  /// Podcast artwork keyed by title, for shows whose episode rows carry none.
  ///
  /// EpisodeDownloadModel only gets `imageURL` when the row is created by the
  /// download path, which looks the podcast up first. The row created by
  /// merely *playing* an episode (PlaybackStateCoordinator.savePlaybackPosition)
  /// passes only title/podcast/audioURL, and the one created from an incoming
  /// iCloud progress record knows even less — so every episode you streamed,
  /// or listened to on another device, has a nil imageURL. Measured on a real
  /// library: 55 of 55 rows feeding this screen, which is why the artwork was
  /// never anything but a placeholder.
  ///
  /// Resolved here rather than by backfilling the model: this screen groups by
  /// podcast, so the show's own artwork is the right image regardless of which
  /// episode happened to create the row.
  private func podcastArtworkByTitle(
    for titles: some Collection<String>, context: ModelContext
  ) -> [String: String] {
    guard !titles.isEmpty else { return [:] }
    let wanted = Set(titles)
    // `title` and `imageURL` are stored properties; this deliberately never
    // touches `podcastInfo`, whose blob decode is expensive enough to have
    // hung the Library screen before.
    let podcasts = (try? context.fetch(FetchDescriptor<PodcastInfoModel>())) ?? []
    var result: [String: String] = [:]
    for podcast in podcasts where wanted.contains(podcast.title) && !podcast.imageURL.isEmpty {
      result[podcast.title] = podcast.imageURL
    }
    return result
  }

  private func buildWeeklyBuckets(from models: [EpisodeDownloadModel]) -> [WeeklyListeningBucket] {
    let cal = Calendar.current
    var bucketMap: [Date: Double] = [:]  // key = Monday of that week

    for model in models {
      guard let date = model.lastPlayedDate else { continue }
      let weekStart = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
      // Normalise to midnight Monday
      let monday = cal.startOfDay(for: weekStart)

      let duration = model.duration > 0 ? model.duration : model.lastPlaybackPosition
      let completedPlays = model.isCompleted ? max(model.playCount, 1) : model.playCount
      let listeningTime = duration * Double(completedPlays) + (model.isCompleted ? 0 : model.lastPlaybackPosition)
      bucketMap[monday, default: 0] += listeningTime / 3600.0
    }

    return bucketMap
      .map { WeeklyListeningBucket(weekStart: $0.key, hours: $0.value) }
      .sorted { $0.weekStart < $1.weekStart }
  }

  // MARK: - Streak

  private func computeLongestStreak(from models: [EpisodeDownloadModel]) -> Int {
    let cal = Calendar.current
    let days = Set(models.compactMap { $0.lastPlayedDate }.map { cal.startOfDay(for: $0) })
    guard !days.isEmpty else { return 0 }

    let sorted = days.sorted()
    var longest = 1
    var current = 1

    for i in 1..<sorted.count {
      if cal.dateComponents([.day], from: sorted[i - 1], to: sorted[i]).day == 1 {
        current += 1
        longest = max(longest, current)
      } else {
        current = 1
      }
    }
    return longest
  }
}
