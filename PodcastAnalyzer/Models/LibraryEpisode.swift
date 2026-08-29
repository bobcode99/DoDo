//
//  LibraryEpisode.swift
//  PodcastAnalyzer
//
//  One row in the Library's Saved / Downloaded / Latest lists, plus its
//  conversion into the playback shape.
//

import Foundation

struct LibraryEpisode: Identifiable, Hashable {
  static func == (lhs: LibraryEpisode, rhs: LibraryEpisode) -> Bool {
    lhs.id == rhs.id
  }
  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  let id: String
  let podcastTitle: String
  let imageURL: String?
  let language: String
  let episodeInfo: PodcastEpisodeInfo
  let isStarred: Bool
  let isDownloaded: Bool
  let isCompleted: Bool
  let lastPlaybackPosition: TimeInterval
  /// Actual duration measured by AVPlayer and stored in SwiftData.
  /// More accurate than `episodeInfo.duration` which comes from potentially
  /// wrong RSS metadata. Zero means not yet measured.
  let savedDuration: TimeInterval

  var hasProgress: Bool {
    lastPlaybackPosition > 0 && !isCompleted
  }

  /// Progress percentage (0.0 to 1.0).
  /// Prefers `savedDuration` (measured by AVPlayer) over RSS metadata duration.
  var progress: Double {
    let dur: Double
    if savedDuration > 0 {
      dur = savedDuration
    } else if let rss = episodeInfo.duration, rss > 0 {
      dur = Double(rss)
    } else {
      return 0
    }
    return min(lastPlaybackPosition / dur, 1.0)
  }
}

// MARK: - Playback Conversion

extension PlaybackEpisode {
  /// The queue/playback shape of a library row. `nil` when the episode has no
  /// audio URL — every caller already has to guard that case, so the failable
  /// init keeps the check in one place instead of at each menu action.
  init?(_ episode: LibraryEpisode) {
    guard let audioURL = episode.episodeInfo.audioURL else { return nil }
    self.init(
      id: episode.id,
      title: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle,
      audioURL: audioURL,
      imageURL: episode.imageURL,
      episodeDescription: episode.episodeInfo.podcastEpisodeDescription,
      pubDate: episode.episodeInfo.pubDate,
      duration: episode.episodeInfo.duration,
      guid: episode.episodeInfo.guid
    )
  }
}
