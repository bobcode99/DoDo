//
//  EpisodeDownloadModel.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

//
//  EpisodeDownloadModel.swift
//  PodcastAnalyzer
//
//  SwiftData model to track downloads and playback state
//

import Foundation
import SwiftData

@Model
class EpisodeDownloadModel {
  // Indexes for the hot query paths: lookup by composite `id`, per-podcast
  // lists, the Saved/Downloaded filters, and "most recently played" sorting.
  #Index<EpisodeDownloadModel>([\.id], [\.podcastTitle], [\.isStarred], [\.localAudioPath], [\.lastPlayedDate])

  var id: String = ""

  var episodeTitle: String = ""
  var podcastTitle: String = ""
  var audioURL: String = ""
  var localAudioPath: String?
  var captionPath: String?

  // Playback state
  var lastPlaybackPosition: TimeInterval = 0
  var duration: TimeInterval = 0
  var isCompleted: Bool = false
  var lastPlayedDate: Date?
  var playCount: Int = 0

  // User preferences
  var isStarred: Bool = false
  var notes: String?

  // Download metadata
  var downloadedDate: Date?
  var fileSize: Int64 = 0

  /// When non-nil, the user dismissed this episode from Up Next via swipe-to-Remove.
  /// The list filter resurfaces it if `lastPlayedDate` later moves past this timestamp,
  /// matching Apple Podcasts' behavior where replaying a removed item brings it back.
  var upNextDismissedAt: Date?

  // Transcript metadata
  var transcriptSource: String = ""     // "" = unknown, "rss" = from RSS, "local" = generated locally

  // Episode metadata (cached)
  var imageURL: String?
  var pubDate: Date?

  /// AntennaPod pattern: set to false after auto-download succeeds so the
  /// episode is never auto-downloaded again. Manual download always works.
  var autoDownloadEnabled: Bool = true

  init(
    episodeTitle: String,
    podcastTitle: String,
    audioURL: String,
    localAudioPath: String? = nil,
    captionPath: String? = nil,
    lastPlaybackPosition: TimeInterval = 0,
    duration: TimeInterval = 0,
    isCompleted: Bool = false,
    lastPlayedDate: Date? = nil,
    playCount: Int = 0,
    isStarred: Bool = false,
    notes: String? = nil,
    downloadedDate: Date? = nil,
    fileSize: Int64 = 0,
    imageURL: String? = nil,
    pubDate: Date? = nil,
    autoDownloadEnabled: Bool = true,
    upNextDismissedAt: Date? = nil
  ) {
    // Use Unit Separator (U+001F) as delimiter - same as DownloadManager
    // Fall back to | for backward compatibility with existing data
    let delimiter = "\u{1F}"
    self.id = "\(podcastTitle)\(delimiter)\(episodeTitle)"
    self.episodeTitle = episodeTitle
    self.podcastTitle = podcastTitle
    self.audioURL = audioURL
    self.localAudioPath = localAudioPath
    self.captionPath = captionPath
    self.lastPlaybackPosition = lastPlaybackPosition
    self.duration = duration
    self.isCompleted = isCompleted
    self.lastPlayedDate = lastPlayedDate
    self.playCount = playCount
    self.isStarred = isStarred
    self.notes = notes
    self.downloadedDate = downloadedDate
    self.fileSize = fileSize
    self.imageURL = imageURL
    self.pubDate = pubDate
    self.autoDownloadEnabled = autoDownloadEnabled
    self.upNextDismissedAt = upNextDismissedAt
  }

  /// Progress percentage (0.0 to 1.0)
  var progress: Double {
    guard duration > 0 else { return 0 }
    return min(lastPlaybackPosition / duration, 1.0)
  }

  /// True only when the local file path exists on this device.
  var hasLocalAudioFile: Bool {
    guard let path = localAudioPath, !path.isEmpty else { return false }
    return FileManager.default.fileExists(atPath: path)
  }

  /// Formatted remaining time (always shows seconds)
  var remainingTimeString: String? {
    guard duration > 0 else { return nil }
    let remaining = duration - lastPlaybackPosition
    if remaining <= 0 { return nil }

    let totalSeconds = Int(remaining)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return "\(hours)h \(minutes)m \(seconds)s left"
    }
    return "\(minutes)m \(seconds)s left"
  }
}
