//
//  MacTrendingEpisodesGrid.swift
//  PodcastAnalyzer
//
//  Created by JunNianLo on 2026/5/16.
//


import SwiftData
import SwiftUI

/// macOS-only grid for the Top Episodes section. Lays the (up to) 12 episodes
/// out as 3 rows × N columns and lets the user scroll horizontally. The fourth
/// column peeks ~20% into view so the horizontal scroll affordance is
/// discoverable without a visible scrollbar.
struct MacTrendingEpisodesGrid: View {
  let episodes: [ApplePodcastService.TrendingEpisode]

  /// `LazyHGrid` with three rows fills items column-by-column: 1/2/3 in the
  /// first column, 4/5/6 in the second, etc. — which is the layout the user
  /// asked for.
  private let rows: [GridItem] = Array(
    repeating: GridItem(.flexible(minimum: 56), spacing: 4),
    count: 3
  )

  /// Visible columns including the partial 4th column hint (0.2 = 20%).
  private let visibleColumns: CGFloat = 3.2
  private let columnSpacing: CGFloat = 16
  private let rowHeight: CGFloat = 68

  var body: some View {
    ScrollView(.horizontal) {
      LazyHGrid(rows: rows, spacing: columnSpacing) {
        ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
          macTrendingCell(episode: episode, rank: index + 1)
            .containerRelativeFrame(.horizontal) { length, _ in
              // Divide the visible container so 3 columns fully fit and the
              // 4th peeks at 20%. Spacing between visible columns is taken
              // out of the budget so the math stays honest.
              let spacingBudget = (visibleColumns - 1) * columnSpacing
              return max((length - spacingBudget) / visibleColumns, 240)
            }
        }
      }
      .scrollTargetLayout()
      .padding(.horizontal, 24)
    }
    .scrollIndicators(.never)
    .frame(height: rowHeight * 3 + 8)
  }

  @ViewBuilder
  private func macTrendingCell(
    episode: ApplePodcastService.TrendingEpisode,
    rank: Int
  ) -> some View {
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
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
    }
    .contextMenu {
      TrendingEpisodeContextMenu(episode: episode)
    }
  }
}