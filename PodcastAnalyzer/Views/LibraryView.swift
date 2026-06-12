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
  @State private var showTranscriptProgressSheet = false
  @AppStorage("showEpisodeArtwork") private var showEpisodeArtwork = true
  @Environment(\.modelContext) private var modelContext

  @Query(
    filter: #Predicate<PodcastInfoModel> { $0.isSubscribed },
    sort: \.lastUpdated,
    order: .reverse
  ) private var subscribedPodcasts: [PodcastInfoModel]

  @State private var sortedPodcasts: [PodcastGridItem] = []
  @State private var podcastModelByID: [PodcastInfoModel.ID: PodcastInfoModel] = [:]
  /// (id → lastUpdated) of the last podcast snapshot we processed. Lets us skip
  /// re-sorting and re-mapping on the second+ time the user enters the tab when
  /// nothing has changed — the @Query emits a new array on every SwiftData
  /// write, even unrelated ones. Tracking lastUpdated (not just ids) means a
  /// background feed sync still refreshes the grid's latest-episode dates.
  @State private var lastProcessedPodcastStamp: [PodcastInfoModel.ID: Date] = [:]
  /// Throttles the saved/downloaded re-fetch in onAppear: popping back from a
  /// sub-page re-fires onAppear, and running SwiftData fetches during the nav
  /// transition is what makes the pop animation hitch.
  @State private var lastAppearRefresh = Date.distantPast
  @State private var errorMessage: String?
  @State private var showError = false

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
      } else if subscribedPodcasts.isEmpty
                && viewModel.savedEpisodes.isEmpty
                && viewModel.downloadedEpisodes.isEmpty {
        ContentUnavailableView {
          Label("No Podcasts Yet", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
          Text("Search for a show or paste an RSS feed URL to start building your library.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformBackground)
      }
    }
    .navigationTitle(Constants.libraryString)
    .platformToolbarTitleDisplayMode()
    .toolbar {
      ToolbarItem(placement: .navigation) {
        SyncProgressToolbarBadge()
      }
      ToolbarItem(placement: .navigation) {
        // Isolated subview observes TranscriptManager so progress ticks don't
        // invalidate the entire LibraryView body on every update.
        TranscriptToolbarBadge(showSheet: $showTranscriptProgressSheet)
      }
    }
    .sheet(isPresented: $showTranscriptProgressSheet) {
      TranscriptGenerationProgressOverallView()
    }
    .navigationDestination(for: LibrarySubpageRoute.self) { route in
      switch route {
      case .saved:
        SavedEpisodesView(viewModel: viewModel, showEpisodeArtwork: showEpisodeArtwork)
      case .downloaded:
        DownloadedPodcastsGridView(viewModel: viewModel)
      case .downloadedPodcast(let podcastTitle):
        DownloadedEpisodesView(
          viewModel: viewModel,
          showEpisodeArtwork: showEpisodeArtwork,
          podcastTitleFilter: podcastTitle
        )
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
      applyPodcastsIfChanged(subscribedPodcasts)
      // Re-fetch saved/starred episodes so stars set from Home/Search/Trending
      // (outside the Library tab) surface on return. Deferred past the nav
      // transition and throttled, so popping back from a sub-page doesn't run
      // SwiftData fetches mid-animation — that contention was the visible
      // hitch when navigating back into this tab.
      let now = Date()
      guard now.timeIntervalSince(lastAppearRefresh) > 2 else { return }
      lastAppearRefresh = now
      Task {
        try? await Task.sleep(for: .milliseconds(350))
        await viewModel.refreshSavedEpisodes()
        await viewModel.refreshDownloadedEpisodes()
      }
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
      withAnimation(.easeInOut(duration: 0.3)) {
        applyPodcastsIfChanged(newPodcasts)
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

  /// Apply a new subscribed-podcasts snapshot only if the (id, lastUpdated)
  /// signature actually changed. Cheap identity check that skips the expensive
  /// map+sort, the dictionary rebuild, and the viewModel refresh on every
  /// body re-eval.
  private func applyPodcastsIfChanged(_ podcasts: [PodcastInfoModel]) {
    let currentStamp = Dictionary(
      uniqueKeysWithValues: podcasts.map { ($0.id, $0.lastUpdated) }
    )
    guard currentStamp != lastProcessedPodcastStamp else { return }
    lastProcessedPodcastStamp = currentStamp
    podcastModelByID = Dictionary(uniqueKeysWithValues: podcasts.map { ($0.id, $0) })
    viewModel.setPodcasts(podcasts)
    sortedPodcasts = podcasts
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

// MARK: - Isolated transcript toolbar badge

/// Reads `TranscriptManager.shared.activeJobs` only inside this small view, so
/// the high-frequency progress updates re-render only the badge instead of
/// the whole Library screen.
private struct TranscriptToolbarBadge: View {
  @Binding var showSheet: Bool
  @State private var manager = TranscriptManager.shared

  private var activeCount: Int {
    var count = 0
    for job in manager.activeJobs.values {
      switch job.status {
      case .queued, .downloadingModel, .transcribing: count += 1
      case .completed, .failed: break
      }
    }
    return count
  }

  var body: some View {
    let count = activeCount
    if count > 0 {
      Button {
        showSheet = true
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "waveform.badge.plus")
          Text("\(count)")
            .font(.caption2.monospacedDigit())
        }
      }
      .transition(.opacity)
    }
  }
}

#Preview {
  LibraryView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
