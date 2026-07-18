//
//  SearchTabButton.swift
//  PodcastAnalyzer
//
//  Tab enum + segmented tab button for the Search screen.
//

import SwiftUI

enum SearchTab: String, CaseIterable {
    case applePodcasts = "Apple Podcasts"
    case library = "Library"
    case transcripts = "Transcripts"
}

struct SearchTabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            tabLabel
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabLabel: some View {
        let base = Text(title)
            .font(.subheadline)
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

        if isSelected {
            base.glassEffect(Glass.regular.interactive(), in: .rect(cornerRadius: 8))
        } else {
            base
        }
    }
}
