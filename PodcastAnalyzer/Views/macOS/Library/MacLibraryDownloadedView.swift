//
//  MacLibraryDownloadedView.swift
//  PodcastAnalyzer
//
//  macOS Library — Downloaded episodes
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacLibraryDownloadedView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]

  var body: some View {
    MacLibraryEpisodeListView(
      episodes: viewModel.downloadedEpisodes,
      podcastInfoModelList: viewModel.podcastInfoModelList,
      emptyTitle: "No Downloads",
      emptySystemImage: "arrow.down.circle",
      emptyDescription: "Downloaded episodes will appear here for offline listening",
      createIfMissing: false,
      modelContext: modelContext,
      episodeModels: $episodeModels
    )
    .navigationTitle("Downloaded")
    .onAppear {
      viewModel.setModelContext(modelContext)
      episodeModels = LibraryEpisodeActions.batchFetchEpisodeModels(from: modelContext)
      // Same staleness fix as Saved — pick up newly-completed downloads
      // triggered from EpisodeDetailView / DownloadManager elsewhere.
      Task { await viewModel.refreshDownloadedEpisodes() }
    }
    .onDisappear {
      viewModel.cleanup()
    }
  }
}
#endif
