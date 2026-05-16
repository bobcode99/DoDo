import NukeUI
import SwiftData
import SwiftUI
import UIKit

/// Wraps a TrendingEpisodeRow with NavigationLink and inline ellipsis Menu.
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