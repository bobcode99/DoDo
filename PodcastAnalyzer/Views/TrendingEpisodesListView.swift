//
//  TrendingEpisodesListView.swift
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

struct TrendingEpisodesListView: View {
  let episodes: [ApplePodcastService.TrendingEpisode]

  var body: some View {
    List {
      ForEach(Array(episodes.prefix(200).enumerated()), id: \.element.id) { index, episode in
        HStack(spacing: 0) {
          NavigationLink(value: TrendingEpisodeDetailDestination(from: episode)) {
            TrendingEpisodeRow(episode: episode, rank: index + 1)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)

          Menu {
            TrendingEpisodeContextMenu(episode: episode)
          } label: {
            Image(systemName: "ellipsis")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .frame(width: 36, height: 36)
              .contentShape(Rectangle())
          }
        }
        .contextMenu {
          TrendingEpisodeContextMenu(episode: episode)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
      }
    }
    .listStyle(.plain)
    .navigationTitle("Top Episodes")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }
}