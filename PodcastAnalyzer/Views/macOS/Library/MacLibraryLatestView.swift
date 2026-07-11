//
//  MacLibraryLatestView.swift
//  PodcastAnalyzer
//
//  macOS Library — Latest episodes across subscribed podcasts
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacLibraryLatestView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]

  // Latest Episodes derives its rows from the subscribed podcasts' episode
  // arrays. Without injecting them via @Query → setPodcasts, the view model's
  // podcastInfoModelList stays empty and the list renders the empty state.
  @Query(
    filter: #Predicate<PodcastInfoModel> { $0.isSubscribed },
    sort: \.lastUpdated,
    order: .reverse
  ) private var subscribedPodcasts: [PodcastInfoModel]

  var body: some View {
    MacLibraryEpisodeListView(
      episodes: viewModel.latestEpisodes,
      podcastInfoModelList: viewModel.podcastInfoModelList,
      emptyTitle: "No Episodes",
      emptySystemImage: "clock",
      emptyDescription: "Subscribe to podcasts to see latest episodes",
      createIfMissing: true,
      modelContext: modelContext,
      episodeModels: $episodeModels,
      onToggleStar: {
        viewModel.setModelContext(modelContext)
      },
      onEpisodeMutated: {
        viewModel.setModelContext(modelContext)
      }
    )
    .navigationTitle("Latest Episodes")
    .onAppear {
      viewModel.setModelContext(modelContext)
      viewModel.setPodcasts(subscribedPodcasts)
      episodeModels = LibraryEpisodeActions.batchFetchEpisodeModels(from: modelContext)
    }
    .onDisappear {
      viewModel.cleanup()
    }
    .onChange(of: subscribedPodcasts) { _, newPodcasts in
      viewModel.setPodcasts(newPodcasts)
    }
  }
}
#endif
