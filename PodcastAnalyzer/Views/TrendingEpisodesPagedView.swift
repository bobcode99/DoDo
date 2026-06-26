//
//  TrendingEpisodesPagedView.swift
//  PodcastAnalyzer
//
//  Created by JunNianLo on 2026/5/16.
//


import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Horizontal paged scroll: each page shows 3 compact episode rows stacked
/// vertically. Apple Podcasts "Top Episodes" style with artwork, rank, title,
/// and metadata. Row sizing is set by `TrendingEpisodeRow` (compact density).
struct TrendingEpisodesPagedView: View {
  let episodes: [ApplePodcastService.TrendingEpisode]

  /// Three rows; the grid flows items column-by-column so the visible layout
  /// is `1 4 7 10 …` / `2 5 8 11 …` / `3 6 9 12 …`.
  private let rows: [GridItem] = Array(
    repeating: GridItem(.flexible(minimum: 56), spacing: 4),
    count: 3
  )

  /// How much of the next column should be visible so the horizontal-scroll
  /// affordance is discoverable. Sized to reveal the rank (18pt) + spacing
  /// (10pt) + the full 40pt artwork + a small breathing margin so the album
  /// art of the next-column episode reads clearly.
  private let peekWidth: CGFloat = 80
  private let columnSpacing: CGFloat = 16

  var body: some View {
    ScrollView(.horizontal) {
      LazyHGrid(rows: rows, spacing: columnSpacing) {
        ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
          TrendingEpisodeRowWithNav(episode: episode, rank: index + 1)
            .containerRelativeFrame(.horizontal) { length, _ in
              // One column fills the viewport minus a peekWidth slice
              // reserved for the artwork of the next column.
              max(length - peekWidth, 240)
            }
        }
      }
      .scrollTargetLayout()
      .padding(.horizontal)
    }
    .scrollTargetBehavior(.viewAligned)
    .scrollIndicators(.never)
    .frame(height: 210)
  }
}

private struct TrendingEpisodeRowWithNav: View {
  let episode: ApplePodcastService.TrendingEpisode
  let rank: Int

  var body: some View {
    HStack(spacing: 0) {
      NavigationLink(value: TrendingEpisodeDetailDestination(from: episode)) {
        TrendingEpisodeRow(episode: episode, rank: rank)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Menu {
        TrendingEpisodeContextMenu(episode: episode)
      } label: {
        Image(systemName: "ellipsis")
          .font(.caption)
          .foregroundStyle(.tertiary)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
    }
    .contextMenu {
      TrendingEpisodeContextMenu(episode: episode)
    }
  }
}
