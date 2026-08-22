//
//  WidgetPlaybackData.swift
//  PodcastAnalyzer
//
//  Snapshot of what is playing right now. Written to App Group UserDefaults for
//  the widget (see WidgetDataManager) and sent to the watch over
//  WatchConnectivity — both want the same handful of fields, so the type lives
//  here rather than beside either transport.
//

import Foundation

nonisolated struct WidgetPlaybackData: Codable, Sendable {
  let episodeTitle: String
  let podcastTitle: String
  let imageURL: String?
  let audioURL: String?
  let currentTime: TimeInterval
  let duration: TimeInterval
  let isPlaying: Bool
  let lastUpdated: Date

  /// Progress as a value from 0.0 to 1.0
  var progress: Double {
    guard duration > 0 else { return 0 }
    return min(currentTime / duration, 1.0)
  }

  /// Deep link URL to open the expanded player in the app
  var deepLinkURL: URL? {
    URL(string: "podcastanalyzer://expandplayer")
  }

  /// Deep link URL for widget background tap.
  /// Always routes to "nowplaying" so the app navigates to whatever episode is
  /// currently active — not the (possibly stale) episode baked into the widget entry.
  var episodeDetailURL: URL? {
    guard let audioURL, !audioURL.isEmpty else { return nil }
    return URL(string: "podcastanalyzer://nowplaying")
  }

  /// Formatted current time string
  var formattedCurrentTime: String {
    formatTime(currentTime)
  }

  /// Formatted duration string
  var formattedDuration: String {
    formatTime(duration)
  }

  /// Formatted remaining time string
  var formattedRemainingTime: String {
    let remaining = max(0, duration - currentTime)
    return "-" + formatTime(remaining)
  }

  private func formatTime(_ time: TimeInterval) -> String {
    let totalSeconds = Int(time)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%d:%02d", minutes, seconds)
    }
  }
}
