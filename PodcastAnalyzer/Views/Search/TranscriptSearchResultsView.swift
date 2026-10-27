//
//  TranscriptSearchResultsView.swift
//  PodcastAnalyzer
//
//  Transcripts-tab results with the per-show filter.
//

import SwiftUI

struct TranscriptSearchResultsView: View {
    @Bindable var viewModel: TranscriptSearchViewModel
    let podcastTitles: [String]
    let isQueryEmpty: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Filter by Podcast", selection: $viewModel.selectedPodcastFilter) {
                    Text("All Podcasts").tag(String?(nil))
                    ForEach(podcastTitles, id: \.self) { title in
                        Text(title).tag(String?(title))
                    }
                }
                .pickerStyle(.menu)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if isQueryEmpty {
                ContentUnavailableView(
                    "Search episode transcripts",
                    systemImage: "text.magnifyingglass"
                )
            } else if viewModel.isSearching {
                Spacer()
                ProgressView()
                Spacer()
            } else if viewModel.results.isEmpty {
                ContentUnavailableView.search
            } else {
                List {
                    ForEach(viewModel.results) { result in
                        TranscriptResultRow(result: result)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}
