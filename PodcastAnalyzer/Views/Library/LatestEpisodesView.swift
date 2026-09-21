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
    Group {
      if viewModel.latestEpisodes.isEmpty {
        emptyStateView
      } else {
        List(viewModel.filteredLatestEpisodes) { episode in
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

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "clock")
        .font(.system(size: 50))
        .foregroundStyle(.secondary)
      Text("No Episodes")
        .font(.headline)
      Text("Subscribe to podcasts to see latest episodes")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
