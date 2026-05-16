//
//  PopularShowsListView.swift
//  PodcastAnalyzer
//
//  Created by JunNianLo on 2026/5/16.
//


import NukeUI
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PopularShowsListView: View {
  let podcasts: [AppleRSSPodcast]
  var viewModel: HomeViewModel

  var body: some View {
    List {
      ForEach(Array(podcasts.prefix(200).enumerated()), id: \.element.id) { index, podcast in
        TopPodcastRow(
            podcast: podcast,
            rank: index + 1,
            isSubscribed: viewModel.isAlreadySubscribed(podcast),
            onSubscribe: { viewModel.subscribeToPodcast(podcast) }
          )
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
      }
    }
    .listStyle(.plain)
    .navigationTitle("Popular Shows")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }
}