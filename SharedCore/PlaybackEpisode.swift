//
//  PlaybackEpisode.swift
//  PodcastAnalyzer
//
//  The episode shape playback works in, as opposed to the RSS snapshot
//  (`PodcastEpisodeInfo`) or the persisted row (`EpisodeDownloadModel`).
//
//  Lives here rather than beside `EnhancedAudioManager` because `QueueItemModel`
//  converts to and from it, and both are shared with the watch target.
//

import Foundation

struct PlaybackEpisode: Identifiable, Codable, Sendable, Equatable {
  let id: String
  let title: String
  let podcastTitle: String
  let audioURL: String
  var imageURL: String?
  var episodeDescription: String?
  var pubDate: Date?
  var duration: Int?
  var guid: String?
}
