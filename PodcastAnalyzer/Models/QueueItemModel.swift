//
//  QueueItemModel.swift
//  PodcastAnalyzer
//
//  SwiftData model for persisting the Play Next queue across app launches
//

import Foundation
import SwiftData

@Model
class QueueItemModel {
  #Index<QueueItemModel>([\.position])

  var id: String = ""
  var position: Int = 0
  var episodeTitle: String = ""
  var podcastTitle: String = ""
  var audioURL: String = ""
  var imageURL: String?
  var episodeDescription: String?
  var pubDate: Date?
  var duration: Int?
  var guid: String?

  init(from episode: PlaybackEpisode, position: Int) {
    self.id = episode.id
    self.position = position
    self.episodeTitle = episode.title
    self.podcastTitle = episode.podcastTitle
    self.audioURL = episode.audioURL
    self.imageURL = episode.imageURL
    self.episodeDescription = episode.episodeDescription
    self.pubDate = episode.pubDate
    self.duration = episode.duration
    self.guid = episode.guid
  }

  func toPlaybackEpisode() -> PlaybackEpisode {
    PlaybackEpisode(
      id: id,
      title: episodeTitle,
      podcastTitle: podcastTitle,
      audioURL: audioURL,
      imageURL: imageURL,
      episodeDescription: episodeDescription,
      pubDate: pubDate,
      duration: duration,
      guid: guid
    )
  }
}
