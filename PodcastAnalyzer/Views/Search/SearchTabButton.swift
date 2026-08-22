//
//  SearchTabButton.swift
//  PodcastAnalyzer
//
//  Tab enum + segmented tab button for the Search screen.
//

import SwiftUI

enum SearchTab: String, CaseIterable {
    /// Raw values are stable identifiers, never labels. They used to be the
    /// display text, and `Text(String)` does not localize — so these tabs
    /// shipped in English to every locale regardless of the catalog entries
    /// sitting in Localizable.xcstrings.
    case applePodcasts
    case library
    case transcripts

    /// "Podcasts", not "Apple Podcasts": naming another app's product as a tab
    /// inside this one reads as a section belonging to that app, and which
    /// directory backs the search is not something the user is choosing here.
    /// The case name stays honest about where the results come from.
    var title: LocalizedStringKey {
        switch self {
        case .applePodcasts: "Podcasts"
        case .library: "Library"
        case .transcripts: "Transcripts"
        }
    }
}

struct SearchTabButton: View {
    let title: LocalizedStringKey
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
