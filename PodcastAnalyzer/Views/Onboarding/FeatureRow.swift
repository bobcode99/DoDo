//
//  FeatureRow.swift
//  PodcastAnalyzer
//
//  Icon + title + description line used on the onboarding welcome page.
//

#if os(iOS)
import SwiftUI

struct FeatureRow: View {
  let icon: String
  let color: Color
  // LocalizedStringKey, not String: these resolve against the environment
  // locale, which is where LanguageManager's in-app language override lives.
  // `String(localized:)` reads the *system* language instead, so the rows
  // stayed in the device language when the user picked another in Settings.
  let title: LocalizedStringKey
  let description: LocalizedStringKey

  @ScaledMetric private var iconWidth: Double = 36

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(color)
        .frame(width: iconWidth)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .bold()
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
  }
}

#Preview {
  FeatureRow(
    icon: "arrow.down.circle.fill",
    color: .green,
    title: "Download Episodes",
    description: "Save episodes for offline listening"
  )
  .padding()
}

#endif
