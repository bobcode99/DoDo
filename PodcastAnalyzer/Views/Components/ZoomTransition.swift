//
//  ZoomTransition.swift
//  PodcastAnalyzer
//
//  Zoom navigation transitions: a card grows into the screen it opens, and
//  shrinks back into it on the way out. The namespace is shared through the
//  environment because sources (grids, carousels, rows) and destinations
//  (registered in `navigationDestinations()` and HomeView) sit in different
//  branches of the view tree.
//

import SwiftUI

extension EnvironmentValues {
  /// Namespace every card → screen zoom is matched in. `nil` when no ancestor
  /// supplies one, in which case the push keeps the default slide.
  @Entry var zoomNamespace: Namespace.ID?
}

extension View {
  /// Tags this card as the thing its destination zooms out of. `id` must be
  /// stable across renders — a value that changes per access silently breaks
  /// the match and the push falls back to a slide.
  @ViewBuilder
  func zoomSource(id: String, in namespace: Namespace.ID?) -> some View {
    #if os(iOS)
      if let namespace {
        matchedTransitionSource(id: id, in: namespace)
      } else {
        self
      }
    #else
      self
    #endif
  }

  /// Zooms this screen out of the card carrying the same id. Falls back to the
  /// standard push when nothing tagged that id — pushes from search, the mini
  /// player, notifications and context menus have no card to grow from.
  @ViewBuilder
  func zoomDestination(id: String, in namespace: Namespace.ID?) -> some View {
    #if os(iOS)
      if let namespace {
        navigationTransition(.zoom(sourceID: id, in: namespace))
      } else {
        self
      }
    #else
      self
    #endif
  }
}

/// Destination for `PodcastBrowseRoute`.
///
/// A view rather than an inline closure body so it can read the zoom namespace
/// out of the environment — `navigationDestinations()` is a `View` extension
/// and has no environment of its own.
struct PodcastBrowseDestination: View {
  let route: PodcastBrowseRoute

  @Environment(\.zoomNamespace) private var zoomNamespace

  var body: some View {
    Group {
      if let model = route.podcastModel {
        EpisodeListView(podcastModel: model, initialFilter: route.initialFilter)
      } else {
        EpisodeListView(
          podcastName: route.podcastName,
          podcastArtwork: route.artworkURL,
          artistName: route.artistName,
          collectionId: route.collectionId ?? "",
          applePodcastUrl: route.applePodcastURL,
          initialFilter: route.initialFilter
        )
      }
    }
    .zoomDestination(id: route.id, in: zoomNamespace)
  }
}

/// Destination for `EpisodeDetailRoute`.
///
/// Same reason as `PodcastBrowseDestination`: `navigationDestinations()` is a
/// `View` extension, so it cannot read the zoom namespace itself.
struct EpisodeDetailDestination: View {
  let route: EpisodeDetailRoute

  @Environment(\.zoomNamespace) private var zoomNamespace

  var body: some View {
    EpisodeDetailView(
      episode: route.episode,
      podcastTitle: route.podcastTitle,
      fallbackImageURL: route.fallbackImageURL,
      podcastLanguage: route.podcastLanguage ?? "en"
    )
    .zoomDestination(id: route.id, in: zoomNamespace)
  }
}
