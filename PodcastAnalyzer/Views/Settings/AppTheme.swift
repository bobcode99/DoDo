//
//  AppTheme.swift
//  PodcastAnalyzer
//
//  Light / Dark / System appearance override.
//
//  Read once at the app root and applied with `preferredColorScheme`, the same
//  shape as EpisodeRowAppearance and AppAccentColor. "System" is the default and
//  is expressed as nil, because `preferredColorScheme(nil)` genuinely means
//  "follow the device" — unlike `.tint(nil)`, which clears rather than defers.
//

import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .system: "System"
    case .light:  "Light"
    case .dark:   "Dark"
    }
  }

  var systemImage: String {
    switch self {
    case .system: "circle.lefthalf.filled"
    case .light:  "sun.max"
    case .dark:   "moon"
    }
  }

  /// nil follows the device setting.
  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light:  .light
    case .dark:   .dark
    }
  }
}

// MARK: - Storage

enum AppThemeDefaults {
  static let key = "appTheme"
}

private struct AppThemeModifier: ViewModifier {
  @AppStorage(AppThemeDefaults.key) private var raw = AppTheme.system.rawValue

  func body(content: Content) -> some View {
    content.preferredColorScheme(AppTheme(rawValue: raw)?.colorScheme)
  }
}

extension View {
  /// Apply once, at the app root — it has to sit above onboarding as well as
  /// the tab view, or a forced theme would stop at the first screen.
  func appTheme() -> some View {
    modifier(AppThemeModifier())
  }
}
