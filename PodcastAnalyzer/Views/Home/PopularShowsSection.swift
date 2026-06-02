//
//  PopularShowsSection.swift
//  PodcastAnalyzer
//
//  Vertical list of top podcasts for the current region.
//

import SwiftUI

struct PopularShowsSection: View {
  let viewModel: HomeViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
        .padding(.horizontal)

      if viewModel.topPodcasts.isEmpty && !viewModel.isLoadingTopPodcasts {
        emptyState
      } else {
        list
      }
    }
  }

  private var header: some View {
    HStack {
      Text("Popular Shows")
        .font(.title2)
        .fontWeight(.bold)

      Spacer()

      if viewModel.isLoadingTopPodcasts {
        ProgressView()
          .scaleEffect(0.8)
      }

      if !viewModel.topPodcasts.isEmpty {
        NavigationLink(value: PopularShowsDestination()) {
          Text("See All")
            .font(.subheadline)
            .foregroundStyle(.blue)
        }
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "chart.line.uptrend.xyaxis")
        .font(.system(size: 40))
        .foregroundStyle(.gray)
      Text("Unable to load popular shows")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 32)
  }

  private var list: some View {
    LazyVStack(spacing: 0) {
      ForEach(Array(viewModel.topPodcasts.prefix(25).enumerated()), id: \.element.id) { index, podcast in
        TopPodcastRow(
          podcast: podcast,
          rank: index + 1,
          isSubscribed: viewModel.isAlreadySubscribed(podcast),
          onSubscribe: { viewModel.subscribeToPodcast(podcast) }
        )
      }
    }
    .padding(.horizontal)
  }
}
