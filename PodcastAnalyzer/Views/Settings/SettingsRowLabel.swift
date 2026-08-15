//
//  SettingsRowLabel.swift
//  PodcastAnalyzer
//
//  The single row style used by Settings: tinted rounded-square glyph, title,
//  and an optional right-hand value. Matching the system Settings idiom keeps
//  colour meaningful — it identifies the category, it is not decoration.
//

import SwiftUI

struct SettingsRowLabel: View {
  let title: LocalizedStringKey
  let systemImage: String
  let tint: Color
  /// A `Text` rather than a `String` so callers choose per value: `Text("On")`
  /// localises through the environment locale (which is how the in-app language
  /// picker works — `String(localized:)` ignores it and always reads the system
  /// language), while `Text(verbatim:)` passes provider and engine names
  /// through untouched.
  var value: Text?
  var valueTint: Color = .secondary

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 29, height: 29)
        .background(tint, in: .rect(cornerRadius: 7))

      Text(title)

      if let value {
        Spacer(minLength: 8)
        value
          .font(.subheadline)
          .foregroundStyle(valueTint)
          .lineLimit(1)
      }
    }
  }
}
