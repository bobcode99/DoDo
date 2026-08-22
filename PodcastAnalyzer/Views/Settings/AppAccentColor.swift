//
//  AppAccentColor.swift
//  PodcastAnalyzer
//
//  User-chosen accent colour.
//
//  `AccentColor.colorset` is compiled into Assets.car and shipped inside the
//  signed bundle, which is read-only — the app cannot rewrite its own asset
//  catalogue. So the choice lives in UserDefaults and is applied with
//  `.tint(_:)` at the app root, with the asset remaining the shipped default.
//  `.tint` is also the current API; `.accentColor` has been deprecated since
//  iOS 15.
//
//  Read exactly once, at the root, and pushed down the environment — same
//  reasoning as EpisodeRowAppearance: `@AppStorage` in a leaf view registers a
//  UserDefaults observer per visible row and tears it down on every scroll.
//  Changing the tint writes one environment value and invalidates only the
//  views that read it, and only when the user actually picks a colour.
//

import SwiftUI

// MARK: - Storage

enum AppAccentColorDefaults {
  /// Archived as "r,g,b" in sRGB. Absent means "System Default", which is the
  /// shipped behaviour and the reason this is optional rather than seeded with
  /// a colour on first launch.
  ///
  /// System Default is the monochrome `AccentColor` asset: white in dark mode,
  /// near-black in light. A literal white in both would be invisible against a
  /// light background — white checkmarks on white — so "white" is expressed as
  /// the adaptive pair, which is white everywhere white is legible.
  static let key = "appAccentColor"

  static func encode(_ color: Color) -> String {
    let resolved = color.resolve(in: .init())
    return "\(resolved.red),\(resolved.green),\(resolved.blue)"
  }

  static func decode(_ raw: String) -> Color? {
    let parts = raw.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 3 else { return nil }
    return Color(.sRGB, red: parts[0], green: parts[1], blue: parts[2])
  }
}

// MARK: - Presets

/// A small set worth one tap. The palette deliberately stays in the range
/// podcast apps actually use — the accent belongs on controls, not on chrome,
/// so these are saturated enough to read as interactive and no further.
enum AccentPreset: String, CaseIterable, Identifiable {
  case indigo, blue, teal, green, orange, red, pink

  var id: String { rawValue }

  var color: Color {
    switch self {
    case .indigo: Color(.sRGB, red: 0.373, green: 0.267, blue: 0.800)
    case .blue:   Color(.sRGB, red: 0.000, green: 0.478, blue: 1.000)
    case .teal:   Color(.sRGB, red: 0.000, green: 0.588, blue: 0.588)
    case .green:  Color(.sRGB, red: 0.126, green: 0.588, blue: 0.278)
    case .orange: Color(.sRGB, red: 0.900, green: 0.451, blue: 0.078)
    case .red:    Color(.sRGB, red: 0.839, green: 0.216, blue: 0.208)
    case .pink:   Color(.sRGB, red: 0.859, green: 0.216, blue: 0.502)
    }
  }

  var titleKey: LocalizedStringKey {
    switch self {
    case .indigo: "Indigo"
    case .blue:   "Blue"
    case .teal:   "Teal"
    case .green:  "Green"
    case .orange: "Orange"
    case .red:    "Red"
    case .pink:   "Pink"
    }
  }
}

// MARK: - Environment

extension EnvironmentValues {
  /// nil = System Default (the shipped AccentColor asset).
  @Entry var appAccentColor: Color?
}

private struct AppAccentColorModifier: ViewModifier {
  @AppStorage(AppAccentColorDefaults.key) private var raw = ""

  private var accent: Color? {
    raw.isEmpty ? nil : AppAccentColorDefaults.decode(raw)
  }

  func body(content: Content) -> some View {
    // `.tint(nil)` does not mean "fall back to the AccentColor asset" — it
    // clears the tint, and `.borderedProminent` then fills with a default grey.
    // For System Default the modifier must not be applied at all, so the asset
    // keeps supplying the accent.
    if let accent {
      content
        .environment(\.appAccentColor, accent)
        .tint(accent)
    } else {
      content
        .environment(\.appAccentColor, nil)
    }
  }
}

extension View {
  /// Apply once, at the app root.
  func appAccentColor() -> some View {
    modifier(AppAccentColorModifier())
  }
}
