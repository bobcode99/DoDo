//
//  DownloadingEpisode.swift
//  PodcastAnalyzer
//
//  An in-flight download shown in the Library's active-downloads list.
//

import Foundation

struct DownloadingEpisode: Identifiable {
  let id: String
  let episodeTitle: String
  let podcastTitle: String
  let imageURL: String?
  let progress: Double
  let state: DownloadState
}
