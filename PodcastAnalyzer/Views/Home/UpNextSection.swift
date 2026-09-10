//
//  UpNextSection.swift
//  PodcastAnalyzer
//
//  "Up Next" horizontal carousel on the Home tab.
//

import SwiftUI

struct UpNextSection: View {
  let viewModel: HomeViewModel

  @Environment(\.zoomNamespace) private var zoomNamespace

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
        .padding(.horizontal)

      if viewModel.upNextEpisodes.isEmpty {
        emptyState
      } else {
        carousel
      }
    }
  }

  private var header: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Up Next")
          .font(.title2)
          .fontWeight(.bold)
        if viewModel.continueListeningCount > 0 {
          Text("\(viewModel.continueListeningCount) in progress")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      if !viewModel.upNextEpisodes.isEmpty {
        NavigationLink(value: UpNextListRoute(episodes: viewModel.upNextEpisodes)) {
          Text("See All")
            .font(.subheadline)
            .foregroundStyle(.blue)
        }
      }
    }
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "play.circle")
        .font(.system(size: 40))
        .foregroundStyle(.gray)
      Text("No unplayed episodes")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Text("Subscribe to podcasts to see new episodes here")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 32)
  }

  private var carousel: some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 12) {
        ForEach(viewModel.scoredUpNextEpisodes.prefix(10)) { scored in
          let route = EpisodeDetailRoute(
            episode: scored.episode.episodeInfo,
            podcastTitle: scored.episode.podcastTitle,
            fallbackImageURL: scored.episode.imageURL,
            podcastLanguage: scored.episode.language,
            zoomsFromSource: true
          )
          NavigationLink(value: route) {
            UpNextCard(
              episode: scored.episode,
              onPlay: { viewModel.playEpisode(scored.episode) },
              reason: scored.reason
            )
          }
          .buttonStyle(.plain)
          .contextMenu {
            UpNextRowContextMenu(episode: scored.episode, viewModel: viewModel)
          }
          // Outside the context menu, not inside it: the menu wraps the card in
          // its own container, and a transition source buried in there is not
          // found at push time, so the zoom silently falls back to a slide.
          .zoomSource(id: route.id, in: zoomNamespace)
        }
      }
      .padding(.horizontal)
    }
    .scrollIndicators(.never)
    .animation(.default, value: viewModel.scoredUpNextIDs)
  }
}
