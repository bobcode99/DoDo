//
//  SavedEpisodesView.swift
//  PodcastAnalyzer
//
//  Saved (starred) episodes sub-page in Library.
//

import SwiftData
import SwiftUI

struct SavedEpisodesView: View {
  @Bindable var viewModel: LibraryViewModel
  let showEpisodeArtwork: Bool
  @Environment(\.modelContext) private var modelContext
  @State private var episodeToDelete: LibraryEpisode?
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]
  @State private var refreshTask: Task<Void, Never>?

  var body: some View {
    let episodes = viewModel.filteredSavedEpisodes
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
              LibraryEpisodeActions.toggleStar(episode, episodeModels: &episodeModels, context: modelContext)
              refreshTask?.cancel()
              refreshTask = Task { await viewModel.refreshSavedEpisodes() }
            },
            onDownload: { LibraryEpisodeActions.downloadEpisode(episode) },
            onDeleteRequested: { episodeToDelete = episode },
            onTogglePlayed: {
              LibraryEpisodeActions.togglePlayed(episode, episodeModels: &episodeModels, context: modelContext)
              refreshTask?.cancel()
              refreshTask = Task { await viewModel.refreshSavedEpisodes() }
            }
          )
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
        .listStyle(.plain)
        .refreshable {
          await viewModel.refreshSavedEpisodes()
        }
      }
    }
    .navigationTitle("Saved")
    .searchable(text: $viewModel.savedSearchText, prompt: "Search saved episodes")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear {
      viewModel.setModelContext(modelContext)
      episodeModels = LibraryEpisodeActions.batchFetchEpisodeModels(from: modelContext)
      // Refresh on every appearance — including pop-back from EpisodeDetailView
      // — so stars toggled in the detail view (especially on episodes from
      // unsubscribed podcasts) show up here without an app restart. `.task`
      // doesn't help here because NavigationStack preserves this view's
      // identity across the push, so the task never re-fires on pop-back.
      refreshTask?.cancel()
      refreshTask = Task { await viewModel.refreshSavedEpisodes() }
    }
    .onDisappear {
      refreshTask?.cancel()
    }
    .confirmationDialog("Delete Download", item: $episodeToDelete, titleVisibility: .visible) { episode in
      Button("Delete", role: .destructive) {
        LibraryEpisodeActions.deleteDownload(episode, episodeModels: episodeModels, context: modelContext)
        refreshTask?.cancel()
        refreshTask = Task { await viewModel.refreshSavedEpisodes() }
      }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("Are you sure you want to delete this downloaded episode?")
    }
  }

  @ViewBuilder
  private var emptyStateView: some View {
    if viewModel.savedSearchText.isEmpty {
      ContentUnavailableView(
        "No Saved Episodes",
        systemImage: "star",
        description: Text("Star episodes to save them here for later")
      )
    } else {
      ContentUnavailableView.search
    }
  }
}
