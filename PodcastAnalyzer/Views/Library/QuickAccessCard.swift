//
//  QuickAccessCard.swift
//  PodcastAnalyzer
//
//  Saved / Downloaded shortcut card at the top of the Library tab.
//

import SwiftUI

struct QuickAccessCard: View {
  let icon: String
  let iconColor: Color
  let title: LocalizedStringKey
  let count: Int
  var isLoading: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: icon)
          .font(.title3)
          .foregroundStyle(iconColor)

        Spacer()

        if isLoading {
          ProgressView()
            .scaleEffect(0.6)
        } else {
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)

        Text("\(count) episodes")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 90)
    .glassEffect(Glass.regular, in: .rect(cornerRadius: 12))
  }
}
