//
//  MacLibrarySavedView.swift
//  PodcastAnalyzer
//
//  macOS Library — Saved (starred) episodes
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacLibrarySavedView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]

  var body: some View {
    MacLibraryEpisodeListView(
      episodes: viewModel.savedEpisodes,
      podcastInfoModelList: viewModel.podcastInfoModelList,
      emptyTitle: "No Saved Episodes",
      emptySystemImage: "star",
      emptyDescription: "Star episodes to save them here for later",
      createIfMissing: false,
      modelContext: modelContext,
      episodeModels: $episodeModels,
      onToggleStar: {
        Task { await viewModel.refreshSavedEpisodes() }
      }
    )
    .navigationTitle("Saved")
    .onAppear {
      viewModel.setModelContext(modelContext)
      episodeModels = LibraryEpisodeActions.batchFetchEpisodeModels(from: modelContext)
      // `setModelContext` no-ops on subsequent visits (`isAlreadyLoaded` short
      // circuits it). Without an explicit refresh here, a star toggled in
      // EpisodeDetailView — including on episodes from unsubscribed podcasts —
      // wouldn't show up until the next app launch.
      Task { await viewModel.refreshSavedEpisodes() }
    }
    .onDisappear {
      viewModel.cleanup()
    }
  }
}
#endif
