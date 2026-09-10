//
//  PodcastGridItem.swift
//  PodcastAnalyzer
//
//  Value-type snapshot backing the Library podcast grid.
//

import Foundation

/// Value-type snapshot passed to PodcastGridCell to prevent @Observable observation
/// storms. LibraryView converts [PodcastInfoModel] → [PodcastGridItem] once in
/// applyPodcastsIfChanged(_:), so SwiftUI only tracks the cheap value array, not the
/// live model's episode array.
struct PodcastGridItem: Identifiable, Equatable {
  let id: UUID
  let title: String
  let imageURL: String
  let episodeCount: Int
  let latestEpisodeDate: Date?

  init(from model: PodcastInfoModel) {
    self.id = model.id
    // Fast path: read the denormalized mirrors so the grid never decodes the
    // podcastInfo episode blob (the cold-load hang). Rows persisted before
    // these columns existed fall back to a one-time decode; LibraryViewModel
    // .loadAllPodcasts backfills them so subsequent launches take the fast path.
    if model.episodeCount > 0 || !model.imageURL.isEmpty {
      self.title = model.title
      self.imageURL = model.imageURL
      self.episodeCount = model.episodeCount
      self.latestEpisodeDate = model.latestEpisodeDate
    } else {
      let info = model.podcastInfo
      self.title = info.title
      self.imageURL = info.imageURL
      self.episodeCount = info.episodes.count
      self.latestEpisodeDate = info.episodes.lazy.compactMap(\.pubDate).max()
    }
  }
}
