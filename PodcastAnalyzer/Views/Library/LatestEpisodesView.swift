//
//  LatestEpisodesView.swift
//  PodcastAnalyzer
//
//  Latest episodes sub-page in Library.
//

import SwiftData
import SwiftUI

struct LatestEpisodesView: View {
  @Bindable var viewModel: LibraryViewModel
  let showEpisodeArtwork: Bool
  @Environment(\.modelContext) private var modelContext
  @State private var episodeToDelete: LibraryEpisode?
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]

  var body: some View {
    let episodes = viewModel.filteredLatestEpisodes
    Group {
      if episodes.isEmpty {
        emptyStateView
      } else {
        List(episodes) { episode in
          EpisodeRowView(
            libraryEpisode: episode,
            episodeModel: episodeModels[episode.id],
            showArtwork: showEpisodeArtwork,
            onToggleStar: {
              LibraryEpisodeActions.toggleStar(episode, episodeModels: &episodeModels, context: modelContext, createIfMissing: true)
              viewModel.setModelContext(modelContext)
            },
            onDownload: { LibraryEpisodeActions.downloadEpisode(episode) },
            onDeleteRequested: { episodeToDelete = episode },
            onTogglePlayed: {
              LibraryEpisodeActions.togglePlayed(episode, episodeModels: &episodeModels, context: modelContext, createIfMissing: true)
              viewModel.setModelContext(modelContext)
            }
          )
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        .listStyle(.plain)
        .refreshable {
          viewModel.setModelContext(modelContext)
        }
      }
    }
    .navigationTitle("Latest Episodes")
    .searchable(text: $viewModel.latestSearchText, prompt: "Search latest episodes")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear {
      viewModel.setModelContext(modelContext)
      episodeModels = LibraryEpisodeActions.batchFetchEpisodeModels(from: modelContext)
    }
    .confirmationDialog("Delete Download", item: $episodeToDelete, titleVisibility: .visible) { episode in
      Button("Delete", role: .destructive) {
        LibraryEpisodeActions.deleteDownload(episode, episodeModels: episodeModels, context: modelContext)
        viewModel.setModelContext(modelContext)
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("Are you sure you want to delete this downloaded episode?")
    }
  }

  @ViewBuilder
  private var emptyStateView: some View {
    if viewModel.latestSearchText.isEmpty {
      ContentUnavailableView(
        "No Episodes",
        systemImage: "clock",
        description: Text("Subscribe to podcasts to see latest episodes")
      )
    } else {
      ContentUnavailableView.search
    }
  }
}
