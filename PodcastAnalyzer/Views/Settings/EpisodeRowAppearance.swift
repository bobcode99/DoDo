//
//  EpisodeRowAppearance.swift
//  PodcastAnalyzer
//
//  Episode-row layout preferences.
//
//  These are read from UserDefaults exactly once, at the app root, and pushed
//  down the environment. Reading `@AppStorage` inside EpisodeRowView instead
//  would register a UserDefaults observer per visible row and tear it down on
//  every scroll — the one part of a settings-driven layout that actually costs
//  something. Branching on the resulting value inside body is free.
//

import SwiftUI

/// Which side of the row's status bar the play pill sits on.
enum EpisodeRowPlayButtonEdge: String, CaseIterable, Identifiable {
  case leading
  case trailing

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .leading: "Left"
    case .trailing: "Right"
    }
  }
}

/// Play-pill size. A multiplier rather than fixed metrics so the pill keeps
/// its proportions and Dynamic Type still applies on top.
enum EpisodeRowPlayButtonSize: String, CaseIterable, Identifiable {
  case small
  case medium
  case large

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .small: "Small"
    case .medium: "Medium"
    case .large: "Large"
    }
  }

  var scale: CGFloat {
    switch self {
    case .small: 1.0
    case .medium: 1.25
    case .large: 1.5
    }
  }
}

extension EnvironmentValues {
  @Entry var episodeRowPlayButtonEdge: EpisodeRowPlayButtonEdge = .trailing
  @Entry var episodeRowPlayButtonSize: EpisodeRowPlayButtonSize = .medium
}

// MARK: - Storage

enum EpisodeRowAppearanceDefaults {
  static let edgeKey = "episodeRowPlayButtonEdge"
  static let sizeKey = "episodeRowPlayButtonSize"
}

private struct EpisodeRowAppearanceModifier: ViewModifier {
  @AppStorage(EpisodeRowAppearanceDefaults.edgeKey)
  private var edge = EpisodeRowPlayButtonEdge.trailing.rawValue
  @AppStorage(EpisodeRowAppearanceDefaults.sizeKey)
  private var size = EpisodeRowPlayButtonSize.medium.rawValue

  func body(content: Content) -> some View {
    content
      .environment(\.episodeRowPlayButtonEdge, EpisodeRowPlayButtonEdge(rawValue: edge) ?? .trailing)
      .environment(\.episodeRowPlayButtonSize, EpisodeRowPlayButtonSize(rawValue: size) ?? .medium)
  }
}

extension View {
  /// Apply once, at the app root. Every episode row below reads the
  /// environment instead of UserDefaults.
  func episodeRowAppearance() -> some View {
    modifier(EpisodeRowAppearanceModifier())
  }
}
