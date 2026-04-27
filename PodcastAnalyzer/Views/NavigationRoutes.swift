//
//  NavigationRoutes.swift
//  PodcastAnalyzer
//
//  Shared value-based navigation route types used across iOS and macOS.
//  Value-based NavigationLink(value:) + navigationDestination(for:) prevents
//  the legacy NavigationLink(destination:) from eagerly constructing destination
//  views before the user taps — eliminating the primary source of memory growth
//  when browsing large podcast episode lists.
//

import SwiftUI

// MARK: - Episode Detail Route

/// Navigation route that defers EpisodeDetailView construction until the user
/// actually taps the row. Carrying only value types keeps it cheap to create.
struct EpisodeDetailRoute: Hashable, Identifiable {
  let episode: PodcastEpisodeInfo
  let podcastTitle: String
  let fallbackImageURL: String?
  let podcastLanguage: String?

  var id: String {
    "\(podcastTitle)\u{1F}\(episode.id)"
  }
}

// MARK: - Up Next List Route

/// Carries episodes to UpNextListView lazily — construction is deferred until navigation.
struct UpNextListRoute: Hashable {
  let episodes: [LibraryEpisode]

  static func == (lhs: UpNextListRoute, rhs: UpNextListRoute) -> Bool {
    lhs.episodes.map(\.id) == rhs.episodes.map(\.id)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(episodes.map(\.id))
  }
}

// MARK: - Library Sub-page Routes

/// Identifies which library sub-page to navigate to.
enum LibrarySubpageRoute: Hashable {
  case saved
  case downloaded
  case latest
  case downloadingEpisodes
}

/// Value-based navigation route for EpisodeListView. Using a route type
/// prevents legacy NavigationLink(destination:) from constructing the
/// destination view eagerly before the user actually navigates to it.
struct PodcastBrowseRoute: Hashable, Identifiable {
  /// Non-nil when navigating to a subscribed podcast from the library.
  let podcastModel: PodcastInfoModel?
  /// Non-nil when navigating to an unsubscribed podcast from browse/search.
  let collectionId: String?
  let podcastName: String
  let artistName: String
  let artworkURL: String
  let applePodcastURL: String?
  let initialFilter: EpisodeFilter

  /// Convenience init for a subscribed PodcastInfoModel.
  init(podcastModel: PodcastInfoModel, initialFilter: EpisodeFilter = .all) {
    self.podcastModel = podcastModel
    self.collectionId = nil
    self.podcastName = podcastModel.podcastInfo.title
    self.artistName = ""
    self.artworkURL = podcastModel.podcastInfo.imageURL
    self.applePodcastURL = nil
    self.initialFilter = initialFilter
  }

  /// Convenience init for an unsubscribed podcast from the Apple Podcasts directory.
  init(
    podcastName: String,
    artworkURL: String,
    artistName: String,
    collectionId: String,
    applePodcastURL: String?,
    initialFilter: EpisodeFilter = .all
  ) {
    self.podcastModel = nil
    self.collectionId = collectionId
    self.podcastName = podcastName
    self.artistName = artistName
    self.artworkURL = artworkURL
    self.applePodcastURL = applePodcastURL
    self.initialFilter = initialFilter
  }

  var id: String {
    if let model = podcastModel {
      return model.id.uuidString
    }
    return collectionId ?? podcastName
  }

  // Hashable conformance — PodcastInfoModel is a class so use ObjectIdentifier.
  static func == (lhs: PodcastBrowseRoute, rhs: PodcastBrowseRoute) -> Bool {
    if let lm = lhs.podcastModel, let rm = rhs.podcastModel {
      return ObjectIdentifier(lm) == ObjectIdentifier(rm) && lhs.initialFilter == rhs.initialFilter
    }
    return lhs.collectionId == rhs.collectionId
      && lhs.podcastName == rhs.podcastName
      && lhs.initialFilter == rhs.initialFilter
  }

  func hash(into hasher: inout Hasher) {
    if let model = podcastModel {
      hasher.combine(ObjectIdentifier(model))
      hasher.combine(initialFilter)
    } else {
      hasher.combine(collectionId)
      hasher.combine(podcastName)
      hasher.combine(initialFilter)
    }
  }
}
