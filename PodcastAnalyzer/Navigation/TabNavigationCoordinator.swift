//
//  TabNavigationCoordinator.swift
//  PodcastAnalyzer
//
//  Centralized navigation coordinator that manages per-tab routers
//  and tracks which tab is currently visible.
//

import SwiftUI

enum TabIdentifier: Int {
  case home
  case library
  case analysis
  case settings
  case search
}

@Observable
final class TabNavigationCoordinator {
  var homeRouter = TabRouter()
  var libraryRouter = TabRouter()
  var analysisRouter = TabRouter()
  var settingsRouter = TabRouter()
  var searchRouter = TabRouter()

  var visibleTab: TabIdentifier = .home

  /// Tracks the last episode detail route ID pushed via deep link / widget
  /// to prevent stacking duplicates when the user taps the widget repeatedly.
  var lastDeepLinkedEpisodeRouteID: String?

  var activeRouter: TabRouter {
    router(for: visibleTab)
  }

  func router(for tab: TabIdentifier) -> TabRouter {
    switch tab {
    case .home: homeRouter
    case .library: libraryRouter
    case .analysis: analysisRouter
    case .settings: settingsRouter
    case .search: searchRouter
    }
  }
}

// MARK: - Environment Key

private struct TabNavigationCoordinatorKey: EnvironmentKey {
  static let defaultValue: TabNavigationCoordinator? = nil
}

extension EnvironmentValues {
  var tabNavigationCoordinator: TabNavigationCoordinator? {
    get { self[TabNavigationCoordinatorKey.self] }
    set { self[TabNavigationCoordinatorKey.self] = newValue }
  }
}
