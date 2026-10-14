//
//  FilterChip.swift
//  PodcastAnalyzer
//
//  Capsule filter chip used by the episode list's filter/sort bar.
//

import SwiftUI

struct FilterChip: View {
  let title: LocalizedStringResource
  let icon: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      chipLabel
    }
    .buttonStyle(.plain)
    // Selection is otherwise only a fill colour, which VoiceOver can't see.
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  @ViewBuilder
  private var chipLabel: some View {
    let content = HStack(spacing: 4) {
      // Decorative — `checkmark.circle` (Played) reads as "Selected".
      Image(systemName: icon)
        .font(.caption)
        .accessibilityHidden(true)
      Text(title)
        .font(.caption)
        .fontWeight(isSelected ? .semibold : .regular)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)

    if isSelected {
      content
        .background(Color.blue)
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 16))
    } else {
      content
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
  }
}
