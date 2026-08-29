//
//  DownloadedPodcastGroup.swift
//  PodcastAnalyzer
//
//  One show's downloaded episodes, grouped for the Downloaded grid.
//

import Foundation

struct DownloadedPodcastGroup: Identifiable {
  let title: String
  let imageURL: String?
  let podcast: PodcastInfoModel?
  let downloadCount: Int

  var id: String {
    podcast?.id.uuidString ?? title
  }
}
