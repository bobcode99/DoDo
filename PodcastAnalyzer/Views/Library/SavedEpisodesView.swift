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
  @State private var showDeleteConfirmation = false
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]
  @State private var refreshTask: Task<Void, Never>?

  var body: some View {
    Group {
      if viewModel.savedEpisodes.isEmpty {
        emptyStateView
      } else {
        List(viewModel.filteredSavedEpisodes) { episode in
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
            onDeleteRequested: {
              episodeToDelete = episode
              showDeleteConfirmation = true
            },
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
    .confirmationDialog(
      "Delete Download",
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let episode = episodeToDelete {
          LibraryEpisodeActions.deleteDownload(episode, episodeModels: episodeModels, context: modelContext)
          refreshTask?.cancel()
          refreshTask = Task { await viewModel.refreshSavedEpisodes() }
        }
        episodeToDelete = nil
      }
      Button("Cancel", role: .cancel) {
        episodeToDelete = nil
      }
    } message: {
      Text("Are you sure you want to delete this downloaded episode?")
    }
  }

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "star")
        .font(.system(size: 50))
        .foregroundStyle(.secondary)
      Text("No Saved Episodes")
        .font(.headline)
      Text("Star episodes to save them here for later")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
