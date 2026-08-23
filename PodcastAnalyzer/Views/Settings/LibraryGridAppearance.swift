//
//  LibraryGridAppearance.swift
//  PodcastAnalyzer
//
//  Library podcast grid column count. Same environment-injection pattern as
//  EpisodeRowAppearance: read from UserDefaults once at the app root, pushed
//  down the environment so LibraryPodcastsGrid doesn't register its own
//  UserDefaults observer.
//

import SwiftUI

enum LibraryGridColumns: Int, CaseIterable, Identifiable {
  case two = 2
  case three = 3

  var id: Int { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .two: "2 Columns"
    case .three: "3 Columns"
    }
  }
}

extension EnvironmentValues {
  @Entry var libraryGridColumns: LibraryGridColumns = .two
}

// MARK: - Storage

enum LibraryGridAppearanceDefaults {
  static let columnsKey = "libraryGridColumns"
}

private struct LibraryGridAppearanceModifier: ViewModifier {
  @AppStorage(LibraryGridAppearanceDefaults.columnsKey)
  private var columns = LibraryGridColumns.two.rawValue

  func body(content: Content) -> some View {
    content
      .environment(\.libraryGridColumns, LibraryGridColumns(rawValue: columns) ?? .two)
  }
}

extension View {
  /// Apply once, at the app root.
  func libraryGridAppearance() -> some View {
    modifier(LibraryGridAppearanceModifier())
  }
}
