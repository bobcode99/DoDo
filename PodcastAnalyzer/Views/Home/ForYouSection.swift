//
//  ForYouSection.swift
//  PodcastAnalyzer
//
//  "For You" horizontal carousel powered by on-device recommendations.
//

import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct ForYouSection: View {
  let viewModel: HomeViewModel

  var body: some View {
    if viewModel.showForYouRecommendations
        && (!viewModel.recommendedEpisodes.isEmpty || viewModel.isLoadingRecommendations) {
      VStack(alignment: .leading, spacing: 12) {
        header
          .padding(.horizontal)

        if viewModel.isLoadingRecommendations && viewModel.recommendedEpisodes.isEmpty {
          loadingState
        } else {
          carousel
        }
      }
    }
  }

  private var header: some View {
    HStack {
      Image(systemName: "star.leadinghalf.filled")
        .foregroundStyle(.purple)
      Text("For You")
        .font(.title2)
        .fontWeight(.bold)

      Spacer()

      if viewModel.isLoadingRecommendations {
        ProgressView()
          .scaleEffect(0.8)
      } else {
        Button {
          viewModel.refreshRecommendations()
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
      }
    }
  }

  private var loadingState: some View {
    HStack(spacing: 8) {
      ProgressView()
        .scaleEffect(0.7)
      Text("Finding episodes for you...")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
  }

  private var carousel: some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 12) {
        ForEach(viewModel.recommendedEpisodes) { episode in
          NavigationLink(
            value: EpisodeDetailRoute(
              episode: episode.episodeInfo,
              podcastTitle: episode.podcastTitle,
              fallbackImageURL: episode.imageURL,
              podcastLanguage: episode.language
            )
          ) {
            ForYouCard(episode: episode)
          }
          .buttonStyle(.plain)
          .contextMenu {
            UpNextRowContextMenu(episode: episode, viewModel: viewModel)
          }
        }
      }
      .padding(.horizontal)
    }
    .scrollIndicators(.never)
  }
}
