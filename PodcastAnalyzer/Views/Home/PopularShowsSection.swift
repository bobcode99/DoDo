//
//  PopularShowsSection.swift
//  PodcastAnalyzer
//
//  Vertical list of top podcasts for the current region.
//

import SwiftUI

struct PopularShowsSection: View {
  let viewModel: HomeViewModel

  @State private var subscribeError: String?

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
    // No `.animation` on refresh: rows re-ranked by fresh data would slide, and
    // a sliding row hit-tests at its final spot, so a tap mid-slide opens the
    // show below the finger. Swap in place instead.
    .alert("Subscription Failed", item: $subscribeError) { _ in
      Button("OK", role: .cancel) {}
    } message: { message in
      Text(message)
    }
  }

  private func subscribe(to podcast: AppleRSSPodcast) {
    Task {
      do {
        try await viewModel.subscribe(to: podcast)
      } catch {
        subscribeError = error.localizedDescription
      }
    }
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
        .bold()

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
      ForEach(viewModel.topPodcasts.prefix(25).enumerated(), id: \.element.id) { index, podcast in
        TopPodcastRow(
          podcast: podcast,
          rank: index + 1,
          isSubscribed: viewModel.isAlreadySubscribed(podcast),
          onSubscribe: { subscribe(to: podcast) }
        )
      }
    }
    .padding(.horizontal)
  }
}
