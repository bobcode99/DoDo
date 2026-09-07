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

  /// Zooms this screen out of the card carrying the same id.
  ///
  /// Pass a nil namespace when the push had no tagged card. An unmatched zoom is
  /// not a free no-op — it keeps the source-anchored interactive dismiss that
  /// replaced the edge-swipe pop, and the screen ends up with neither.
  @ViewBuilder
  func zoomDestination(id: String, in namespace: Namespace.ID?) -> some View {
    #if os(iOS)
      if let namespace {
        navigationTransition(.zoom(sourceID: id, in: namespace))
          .background(EdgeSwipeBackRestorer())
      } else {
        self
      }
    #else
      self
    #endif
  }
}

#if os(iOS)
/// Puts UIKit's edge-swipe pop back on a screen pushed with a zoom transition.
///
/// The zoom hands the whole screen to its own source-anchored pan dismiss, which
/// a scrolling destination swallows before it ever starts — so the page ends up
/// with no back gesture at all. Re-enabling the pop recognizer restores the edge
/// swipe alongside the zoom.
private struct EdgeSwipeBackRestorer: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> UIViewController {
    Restorer(popDelegate: context.coordinator)
  }

  func updateUIViewController(_: UIViewController, context _: Context) {}

  func makeCoordinator() -> PopGestureDelegate { PopGestureDelegate() }

  /// Held by the coordinator so it dies with the screen: `delegate` is weak, so
  /// UIKit's own behaviour comes back the moment this page is popped.
  final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
      // Same guard UIKit applies by default — without it the recognizer fires
      // on the root screen and leaves the stack wedged.
      (navigationController?.viewControllers.count ?? 0) > 1
    }
  }

  private final class Restorer: UIViewController {
    private let popDelegate: PopGestureDelegate

    init(popDelegate: PopGestureDelegate) {
      self.popDelegate = popDelegate
      super.init(nibName: nil, bundle: nil)
      view.isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMove(toParent parent: UIViewController?) {
      super.didMove(toParent: parent)
      guard let nav = navigationController else { return }
      popDelegate.navigationController = nav
      nav.interactivePopGestureRecognizer?.delegate = popDelegate
      nav.interactivePopGestureRecognizer?.isEnabled = true
    }
  }
}
#endif

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
    .zoomDestination(id: route.id, in: route.zoomsFromSource ? zoomNamespace : nil)
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
    .zoomDestination(id: route.id, in: route.zoomsFromSource ? zoomNamespace : nil)
  }
}

/// Destination for `EpisodeAIAnalysisRoute`.
///
/// Same reason as the two above: `navigationDestinations()` is a `View`
/// extension, so it cannot read the zoom namespace itself. iOS-only, like the
/// page it wraps — macOS splits the episode detail across its own pages and
/// registers this route in MacContentView.
#if os(iOS)
struct EpisodeAIAnalysisDestination: View {
  let route: EpisodeAIAnalysisRoute

  @Environment(\.zoomNamespace) private var zoomNamespace

  var body: some View {
    EpisodeAIAnalysisPage(
      episode: route.episode,
      podcastTitle: route.podcastTitle,
      fallbackImageURL: route.fallbackImageURL,
      podcastLanguage: route.podcastLanguage ?? "en"
    )
    .zoomDestination(id: route.id, in: zoomNamespace)
  }
}
#endif
