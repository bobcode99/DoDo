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
    // Two things hide this section: the user's own toggle, and hardware that
    // can never run the model. An empty list must not — an empty history or a
    // thrown error would then present as "the feature does not exist", with the
    // refresh button gone too, leaving no way to retry.
    if viewModel.showForYouRecommendations, FoundationModelsAvailability.isSupported {
      VStack(alignment: .leading, spacing: 12) {
        header
          .padding(.horizontal)

        if viewModel.isLoadingRecommendations && viewModel.recommendedEpisodes.isEmpty {
          loadingState
        } else if viewModel.recommendedEpisodes.isEmpty {
          emptyState
        } else {
          list
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

  @ViewBuilder
  private var emptyState: some View {
    let message: LocalizedStringKey = switch viewModel.recommendationFailure {
    case .noHistory:
      "Play an episode or two and suggestions will appear here."
    case .modelUnavailable:
      "Apple Intelligence isn't available on this device right now."
    case .noCandidates:
      "Nothing new to suggest — you're caught up on your shows."
    case .generationFailed, .none:
      "Couldn't build suggestions just now. Try again."
    }

    Text(message)
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal)
      .padding(.vertical, 12)
  }

  /// A short vertical list, not a carousel: three to five picks fit on screen,
  /// and full width is what gives the model's reason room to be read.
  private var list: some View {
    VStack(spacing: 0) {
      ForEach(Array(viewModel.recommendedEpisodes.enumerated()), id: \.element.id) { index, recommendation in
        let episode = recommendation.episode
        NavigationLink(
          value: EpisodeDetailRoute(
            episode: episode.episodeInfo,
            podcastTitle: episode.podcastTitle,
            fallbackImageURL: episode.imageURL,
            podcastLanguage: episode.language
          )
        ) {
          ForYouRow(episode: episode, reason: recommendation.reason)
        }
        .buttonStyle(.plain)
        .contextMenu {
          UpNextRowContextMenu(episode: episode, viewModel: viewModel)
        }

        if index < viewModel.recommendedEpisodes.count - 1 {
          Divider()
        }
      }
    }
    .padding(.horizontal)
  }
}
