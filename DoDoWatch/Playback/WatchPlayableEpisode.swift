//
//  WatchPlayableEpisode.swift
//  DoDoWatch
//
//  What the watch player needs to know about an episode, whichever screen it
//  came from — a feed listing, Up Next, or a download.
//

import Foundation

struct WatchPlayableEpisode: Identifiable, Hashable, Sendable {
  let id: String
  let title: String
  let podcastTitle: String
  let audioURL: String
  var imageURL: String?
  /// Set once the episode is on disk; playback prefers it over the network.
  var localPath: String?

  /// The project-wide composite key (see CLAUDE.md), so a position written
  /// here lands on the same CloudKit row the phone reads.
  var progressKey: String { "\(podcastTitle)\u{1F}\(title)" }

  var playbackURL: URL? {
    if let localPath, FileManager.default.fileExists(atPath: localPath) {
      return URL(fileURLWithPath: localPath)
    }
    return URL(string: audioURL)
  }
}

extension WatchPlayableEpisode {
  init?(episode: PodcastEpisodeInfo, podcastTitle: String) {
    guard let audioURL = episode.audioURL else { return nil }
    self.init(
      id: episode.id,
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: audioURL,
      imageURL: episode.imageURL
    )
  }

  init(queueItem: QueueItemModel) {
    self.init(
      id: queueItem.id,
      title: queueItem.episodeTitle,
      podcastTitle: queueItem.podcastTitle,
      audioURL: queueItem.audioURL,
      imageURL: queueItem.imageURL
    )
  }
}
