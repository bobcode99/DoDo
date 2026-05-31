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
  @State private var syncManager = BackgroundSyncManager.shared
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
  /// Last podcast id-set we processed. Lets us skip re-sorting and re-mapping
  /// on the second+ time the user enters the tab when nothing has changed —
  /// the @Query emits a new array on every SwiftData write, even unrelated ones.
  @State private var lastProcessedPodcastIds: [PodcastInfoModel.ID] = []
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
      if syncManager.isSyncing {
        ToolbarItem(placement: .navigation) {
          HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            if syncManager.syncProgressTotal > 0 {
              Text("\(syncManager.syncProgressCurrent)/\(syncManager.syncProgressTotal)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
          }
          .transition(.opacity)
        }
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
      // Re-fetch saved/starred episodes on every appearance so stars set from
      // Home/Search/Trending (outside the Library tab) surface immediately and
      // the ContentUnavailableView clears once content exists.
      Task {
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

  /// Apply a new subscribed-podcasts snapshot only if the id-set actually
  /// changed. Cheap identity check that skips the expensive map+sort, the
  /// dictionary rebuild, and the viewModel refresh on every body re-eval.
  private func applyPodcastsIfChanged(_ podcasts: [PodcastInfoModel]) {
    let currentIds = podcasts.map(\.id)
    guard currentIds != lastProcessedPodcastIds else { return }
    lastProcessedPodcastIds = currentIds
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
