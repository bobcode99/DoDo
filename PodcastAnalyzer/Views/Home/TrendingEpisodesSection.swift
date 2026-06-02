//
//  TrendingEpisodesSection.swift
//  PodcastAnalyzer
//
//  "Top Episodes" horizontal paged carousel powered by Apple's iTunes feeds.
//

import SwiftUI

struct TrendingEpisodesSection: View {
  let viewModel: HomeViewModel

  var body: some View {
    if viewModel.showTrendingEpisodes
        && (!viewModel.trendingEpisodes.isEmpty || viewModel.isLoadingTrendingEpisodes) {
      VStack(alignment: .leading, spacing: 12) {
        header
          .padding(.horizontal)

        if viewModel.trendingEpisodes.isEmpty && viewModel.isLoadingTrendingEpisodes {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
          .frame(height: 120)
        } else {
          TrendingEpisodesPagedView(
            episodes: Array(viewModel.trendingEpisodes.prefix(12))
          )
        }
      }
    }
  }

  private var header: some View {
    HStack {
      Text("Top Episodes")
        .font(.title2)
        .fontWeight(.bold)

      Spacer()

      if viewModel.isLoadingTrendingEpisodes {
        ProgressView()
          .scaleEffect(0.8)
      }

      if !viewModel.trendingEpisodes.isEmpty {
        NavigationLink(value: TrendingEpisodesDestination()) {
          HStack(spacing: 2) {
            Text("See All")
              .font(.subheadline)
            Image(systemName: "chevron.right")
              .font(.caption)
          }
          .foregroundStyle(.blue)
        }
      }
    }
  }
}
