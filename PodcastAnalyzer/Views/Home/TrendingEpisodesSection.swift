//
//  TrendingEpisodesSection.swift
//  PodcastAnalyzer
//
//  "Top Episodes" horizontal paged carousel powered by Apple's iTunes feeds.
//

import SwiftUI

struct TrendingEpisodesSection: View {
  let viewModel: HomeViewModel

  /// Read here rather than through the view model: `HomeViewModel.showTrendingEpisodes`
  /// is a plain `UserDefaults` read nothing observes, so switching the setting off
  /// in Settings left the section on Home until something else refreshed it.
  @AppStorage("showTrendingEpisodes") private var showTrendingEpisodes = true

  @ScaledMetric(relativeTo: .subheadline) private var placeholderHeight: CGFloat = TrendingEpisodesPagedView.baseHeight

  var body: some View {
    if showTrendingEpisodes
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
          // Same height as TrendingEpisodesPagedView so content below doesn't
          // jump when the episodes land.
          .frame(height: placeholderHeight)
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
        .bold()

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
