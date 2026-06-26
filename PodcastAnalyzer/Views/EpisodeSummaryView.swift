//
//  EpisodeSummaryView.swift
//  PodcastAnalyzer
//
//  Pure summary content (description + optional translation). Used by the
//  iOS Summary landing page and the macOS MacEpisodeDetailView. The host
//  provides the surrounding ScrollView, captures the tap location for
//  inline timestamp links, and mounts the TimestampPopupOverlay.
//

import SwiftUI

struct EpisodeSummaryView: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    @Binding var tappedTimestampSeconds: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let translated = viewModel.translation.translatedDescription {
                VStack(alignment: .leading, spacing: 12) {
                    HTMLTextView(
                        attributedString: NSAttributedString(
                            TimestampUtils.attributedStringWithTimestampLinks(translated)
                        )
                    )

                    Divider()

                    DisclosureGroup("Original") {
                        descriptionView
                            .textSelection(.enabled)
                    }
                    .foregroundStyle(.secondary)
                }
            } else {
                descriptionView
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if let seconds = TimestampUtils.parseTimestampURL(url) {
                tappedTimestampSeconds = seconds
                return .handled
            }
            return .systemAction
        })
    }

    @ViewBuilder
    private var descriptionView: some View {
        switch viewModel.descriptionContent {
        case .loading:
            Text("Loading...")
                .foregroundStyle(.secondary)
        case .empty:
            Text("No description available.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .parsed(let attributedString):
            HTMLTextView(attributedString: attributedString, linkTimestamps: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        }
    }
}
