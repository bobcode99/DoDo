//
//  UpNextAppearance.swift
//  PodcastAnalyzer
//
//  Home "Up Next" card size. Read with @AppStorage in UpNextSection directly:
//  it's one carousel, not a per-row list, so one observer costs nothing.
//

import SwiftUI

enum UpNextCardSize: String, CaseIterable, Identifiable {
  case standard
  case large
  case extraLarge

  static let storageKey = "upNextCardSize"

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .standard: "Standard"
    case .large: "Large"
    case .extraLarge: "Extra Large"
    }
  }

  /// Card and artwork width.
  var width: CGFloat {
    switch self {
    case .standard: 140
    case .large: 180
    case .extraLarge: 220
    }
  }

  /// Bigger cards get the big play pill so the main tap target grows too;
  /// nil keeps the Episode Rows setting.
  var playButtonSize: EpisodeRowPlayButtonSize? {
    self == .standard ? nil : .large
  }
}
