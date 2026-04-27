//
//  LibraryView.swift
//  PodcastAnalyzer
//
//  Library tab - 2x2 grid of podcasts sorted by recent update,
//  with navigation to Saved/Downloaded sub-pages.
//

import SwiftData
import SwiftUI

struct LibraryView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @AppStorage("showEpisodeArtwork") private var showEpisodeArtwork = true
  @Environment(\.modelContext) private var modelContext

  @Query(
    filter: #Predicate<PodcastInfoModel> { $0.isSubscribed },
    sort: \.lastUpdated,
    order: .reverse
  ) private var subscribedPodcasts: [PodcastInfoModel]

  @State private var sortedPodcasts: [PodcastGridItem] = []
  @State private var errorMessage: String?
  @State private var showError = false

  private var podcastModelByID: [PodcastInfoModel.ID: PodcastInfoModel] {
    Dictionary(uniqueKeysWithValues: subscribedPodcasts.map { ($0.id, $0) })
  }

  var body: some View {
    ZStack {
      ScrollView {
        VStack(spacing: 24) {
          LibraryQuickAccessSection(
            savedCount: viewModel.savedEpisodes.count,
            downloadedCount: viewModel.downloadedEpisodes.count + viewModel.downloadingEpisodes.count,
            latestCount: viewModel.latestEpisodes.count
          )
          .padding(.horizontal, 16)

          LibraryPodcastsGrid(
            sortedPodcasts: sortedPodcasts,
            podcastModelByID: podcastModelByID,
            modelContext: modelContext,
            onError: { errorMessage = $0 },
            onUnsubscribed: { viewModel.setModelContext(modelContext) }
          )
          .padding(.horizontal, 16)
        }
        .padding(.top, 8)
        .padding(.bottom, 40)
      }

      if viewModel.isLoading && subscribedPodcasts.isEmpty
          && viewModel.savedEpisodes.isEmpty && viewModel.downloadedEpisodes.isEmpty {
        ProgressView("Loading Library...")
          .scaleEffect(1.5)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.platformBackground)
      }
    }
    .navigationTitle(Constants.libraryString)
    .platformToolbarTitleDisplayMode()
    .navigationDestination(for: LibrarySubpageRoute.self) { route in
      switch route {
      case .saved:
        SavedEpisodesView(viewModel: viewModel, showEpisodeArtwork: showEpisodeArtwork)
      case .downloaded:
        DownloadedPodcastsGridView(viewModel: viewModel)
      case .latest:
        LatestEpisodesView(viewModel: viewModel, showEpisodeArtwork: showEpisodeArtwork)
      case .downloadingEpisodes:
        ActiveDownloadsView(viewModel: viewModel)
      }
    }
    .refreshable {
      await viewModel.refreshAllPodcasts()
    }
    .onAppear {
      viewModel.setModelContext(modelContext)
      viewModel.setPodcasts(subscribedPodcasts)
      updateSortedPodcasts()
    }
    .task {
      // Only run the initial load if it hasn't already been kicked off by setModelContext.
      // Without this guard, every tab re-appearance triggers a full refresh.
      guard !viewModel.isLoaded else { return }
      await viewModel.refreshSavedEpisodes()
      await viewModel.refreshDownloadedEpisodes()
    }
    .task {
      // Modernized notification observers using async sequences
      for await _ in NotificationCenter.default.notifications(named: .podcastSyncCompleted) {
        viewModel.refreshData()
      }
    }
    .onChange(of: errorMessage) { _, newValue in
      showError = newValue != nil
    }
    .onChange(of: subscribedPodcasts) { _, newPodcasts in
      if Set(newPodcasts.map(\.id)) != Set(sortedPodcasts.map(\.id)) {
        viewModel.setPodcasts(newPodcasts)
        withAnimation(.easeInOut(duration: 0.3)) {
          updateSortedPodcasts()
        }
      }
    }

    // Note: Do NOT call viewModel.cleanup() here — LibraryView is a tab root,
    // and pushing a NavigationLink fires onDisappear.  Cleaning up would cancel
    // the download-completion observer while the user is in a sub-page.
    .alert("Error", isPresented: $showError) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
  }

  // MARK: - Helper Methods

  private func updateSortedPodcasts() {
    sortedPodcasts = subscribedPodcasts
      .map { PodcastGridItem(from: $0) }
      .sorted {
        switch ($0.latestEpisodeDate, $1.latestEpisodeDate) {
        case let (lhs?, rhs?): return lhs > rhs
        case (_?, nil):        return true   // dated before undated
        case (nil, _?):        return false
        case (nil, nil):       return false
        }
      }
  }

}

#Preview {
  LibraryView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
