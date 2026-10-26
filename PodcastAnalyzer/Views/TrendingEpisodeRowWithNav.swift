//
//  TrendingEpisodeRowWithNav.swift
//  PodcastAnalyzer
//
//  Created by JunNianLo on 2026/5/16.
//

import SwiftUI

/// Wraps a TrendingEpisodeRow with NavigationLink and inline ellipsis Menu.
struct TrendingEpisodeRowWithNav: View {
  let episode: ApplePodcastService.TrendingEpisode
  let rank: Int

  @Environment(\.zoomNamespace) private var zoomNamespace

  var body: some View {
    let destination = TrendingEpisodeDetailDestination(from: episode)
    HStack(spacing: 0) {
      NavigationLink(value: destination) {
        TrendingEpisodeRow(episode: episode, rank: rank)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)

      Menu {
        TrendingEpisodeContextMenu(episode: episode)
      } label: {
        Label("More options", systemImage: "ellipsis")
          .labelStyle(.iconOnly)
          .font(.caption)
          .foregroundStyle(.tertiary)
          .frame(width: 44, height: 44)
          .contentShape(.rect)
      }
    }
    .contextMenu {
      TrendingEpisodeContextMenu(episode: episode)
    }
    // See TrendingEpisodesListView: the source has to sit outside the context
    // menu, or the zoom silently falls back to a slide.
    .zoomSource(id: destination.id, in: zoomNamespace)
  }
}
