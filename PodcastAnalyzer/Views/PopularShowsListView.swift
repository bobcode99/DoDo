//
//  PopularShowsListView.swift
//  PodcastAnalyzer
//
//  Created by JunNianLo on 2026/5/16.
//


import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PopularShowsListView: View {
  var viewModel: HomeViewModel

  /// Read live from the view model rather than taking a snapshot at push time.
  /// Switching region calls `invalidateDiscoveryContent()`, which empties
  /// `topPodcasts` before the new ones land — a frozen array left this screen
  /// showing the previous country's chart, and an empty one left it blank with
  /// no indication anything was happening. Same reasoning as the Up Next route
  /// in HomeView.swift.
  private var podcasts: [AppleRSSPodcast] { viewModel.topPodcasts }

  var body: some View {
    // Match the Home "Popular Shows" section exactly: TopPodcastRow already draws
    // its own rank, chevron, and trailing divider, so it belongs in a LazyVStack —
    // dropping it in a List doubled the chevron (List's disclosure indicator) and
    // the separator (List's row separator over the row's manual Divider).
    ScrollView {
      if podcasts.isEmpty {
        // The refill window after a region switch, and the offline case.
        // Without this the screen is an empty ScrollView, which reads as broken.
        ContentUnavailableView {
          Label(
            viewModel.isLoadingTopPodcasts ? "Loading Popular Shows" : "No Popular Shows",
            systemImage: viewModel.isLoadingTopPodcasts ? "globe" : "wifi.slash"
          )
        } description: {
          Text(viewModel.isLoadingTopPodcasts
               ? "Fetching the chart for \(viewModel.selectedRegionName)."
               : "Nothing to show for \(viewModel.selectedRegionName) right now.")
        }
        .padding(.top, 48)
      } else {
        LazyVStack(spacing: 0) {
          ForEach(Array(podcasts.prefix(200).enumerated()), id: \.element.id) { index, podcast in
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
    .animation(.smooth(duration: 0.25), value: viewModel.popularShowsFetchedAt)
    .navigationTitle("Popular Shows")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }
}