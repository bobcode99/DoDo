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
      VStack(alignment: .leading, spacing: 2) {
        header
        freshnessCaption
      }
      .padding(.horizontal)

      if viewModel.topPodcasts.isEmpty && !viewModel.isLoadingTopPodcasts {
        emptyState
      } else {
        list
      }
    }
    // Silent swap: when fresh data lands (reconnect / pull-to-refresh) the list
    // updates in place with a gentle crossfade rather than a hard cut.
    .animation(.smooth(duration: 0.25), value: viewModel.popularShowsFetchedAt)
  }

  /// "Updated 2h ago" online, "Offline · saved 2h ago" when showing saved data.
  @ViewBuilder
  private var freshnessCaption: some View {
    if let fetchedAt = viewModel.popularShowsFetchedAt {
      HStack(spacing: 4) {
        if viewModel.isOffline {
          Image(systemName: "wifi.slash")
        }
        Text("\(viewModel.isOffline ? "Offline · saved " : "Updated ")\(fetchedAt, format: .relative(presentation: .named))")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
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
      Image(systemName: viewModel.isOffline ? "wifi.slash" : "chart.line.uptrend.xyaxis")
        .font(.system(size: 40))
        .foregroundStyle(.gray)
      Text(viewModel.isOffline ? "You're offline" : "Unable to load popular shows")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      if viewModel.isOffline {
        Text("Popular shows will appear once you're back online.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
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

