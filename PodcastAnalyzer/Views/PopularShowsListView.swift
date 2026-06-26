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
  let podcasts: [AppleRSSPodcast]
  var viewModel: HomeViewModel

  var body: some View {
    // Match the Home "Popular Shows" section exactly: TopPodcastRow already draws
    // its own rank, chevron, and trailing divider, so it belongs in a LazyVStack —
    // dropping it in a List doubled the chevron (List's disclosure indicator) and
    // the separator (List's row separator over the row's manual Divider).
    ScrollView {
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
    .navigationTitle("Popular Shows")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }
}