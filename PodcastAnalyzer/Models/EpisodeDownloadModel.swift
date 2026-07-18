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

  // Playback state
  var lastPlaybackPosition: TimeInterval = 0
  var duration: TimeInterval = 0
  // didSet stamps lastPlayedDate whenever an episode transitions to completed,
  // regardless of which call site flips it (manual "mark played", playback
  // reaching the end, etc). Without this, only the auto-completion path
  // (PlaybackStateCoordinator) touched lastPlayedDate — every manually
  // marked-played episode kept it nil, so sweepPlayedDownloads()'s grace-window
  // guard (`guard let lastPlayed = model.lastPlayedDate ...`) skipped them
  // forever, no matter how old.
  //
  // Also pushes to iCloud here rather than at each call site: "mark played" /
  // "mark unplayed" are toggled directly on this property from ~8 places
  // (HomeViewModel, EpisodeListViewModel, EpisodeDetailViewModel,
  // LibraryEpisodeActions, TrendingEpisodeContextMenu) and only the automatic
  // playback-position pipeline (PlaybackStateCoordinator) synced — manual
  // toggles were silently local-only. Centralizing here means every future
  // call site gets sync for free instead of needing to remember it.
  var isCompleted: Bool = false {
    didSet {
      guard isCompleted != oldValue else { return }
      if isCompleted {
        lastPlayedDate = Date()
      }
      progressUpdatedAt = Date()
      PlaybackProgressSyncCoordinator.shared.push(from: self, force: true)
    }
  }
  var lastPlayedDate: Date?
  var playCount: Int = 0

  /// Stamped on every local playback-position write (unlike `lastPlayedDate`,
  /// which only moves on completion). Lets `PlaybackProgressSyncCoordinator`
  /// tell whether an incoming CloudKit row is newer than what this device
  /// already knows before overwriting local state.
  var progressUpdatedAt: Date?

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
    // didSet above doesn't fire for values assigned during init, so a caller
    // constructing directly with isCompleted: true (no explicit lastPlayedDate)
    // needs the same fallback stamp here.
    if isCompleted, self.lastPlayedDate == nil {
      self.lastPlayedDate = Date()
    }
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
