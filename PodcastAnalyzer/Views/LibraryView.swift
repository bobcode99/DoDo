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
  /// Recency signature of the last podcast snapshot we processed. Lets us skip
  /// re-sorting and re-mapping on the second+ time the user enters the tab when
  /// nothing has changed — the @Query emits a new array on every SwiftData
  /// write, even unrelated ones.
  @State private var lastProcessedSignature: Int?
  /// Incremented on `.podcastSyncCompleted` to re-check the grid order.
  @State private var syncTick = 0
  /// Throttles the saved/downloaded re-fetch in onAppear: popping back from a
  /// sub-page re-fires onAppear, and running SwiftData fetches during the nav
  /// transition is what makes the pop animation hitch.
  @State private var lastAppearRefresh = Date.distantPast
  /// Built grid items keyed by podcast id, tagged with the `lastUpdated` stamp
  /// they were derived from. Lets `applyPodcastsIfChanged` reuse items for
  /// podcasts that haven't changed and decode the (expensive) `podcastInfo`
  /// blob only for podcasts whose feed actually changed since the last build.
  @State private var gridItemCache: [PodcastInfoModel.ID: CachedGridItem] = [:]
  @State private var errorMessage: String?
  /// Whether this tab is the screen on top. LibraryView is a NavigationStack
  /// root, so it stays subscribed to its `@Query` while EpisodeListView is
  /// pushed over it — see `visibleRecencySignature`.
  @State private var isVisible = false

  var body: some View {
    ZStack {
      ScrollView {
        VStack(spacing: 24) {
          LibraryQuickAccessSection(
            viewModel: viewModel,
            showTranscriptProgressSheet: $showTranscriptProgressSheet
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

      // `sortedPodcasts`, not `subscribedPodcasts`: touching the @Query here ran
      // its fetch a third time per body pass. The two hold the same set — the
      // grid above already renders from this one.
      if viewModel.isLoading && sortedPodcasts.isEmpty
          && viewModel.savedEpisodes.isEmpty && viewModel.downloadedEpisodes.isEmpty {
        ProgressView("Loading Library...")
          .scaleEffect(1.5)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.platformBackground)
      } else if lastProcessedSignature != nil
                && sortedPodcasts.isEmpty
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
      let isFirstLoad = !viewModel.isLoaded
      viewModel.setModelContext(modelContext)

      // First appearance: nothing is on screen and there is no transition to
      // protect, so draw the grid as early as possible.
      guard !isFirstLoad else {
        isVisible = true
        applyPodcastsIfChanged(subscribedPodcasts)
        return
      }

      // Popping back from a sub-page. Every line below reads SwiftData, and
      // flipping `isVisible` alone re-opens the `@Query` — whose getter runs a
      // synchronous fetch, the main-thread `sqlite3_step` this gate exists to
      // avoid. EpisodeListView stamps `lastUpdated` on the show you just left,
      // so that fetch is always invalidated and always does real work: the
      // pop paid for it every single time.
      //
      // Holding `isVisible` false until the transition lands keeps the query
      // parked for the whole animation. The grid then re-sorts a frame later,
      // animated by LibraryPodcastsGrid's own `.animation(.smooth,)`.
      let now = Date()
      let shouldRefreshSections = now.timeIntervalSince(lastAppearRefresh) > 2
      if shouldRefreshSections { lastAppearRefresh = now }
      Task {
        try? await Task.sleep(for: .milliseconds(350))
        isVisible = true
        applyPodcastsIfChanged(subscribedPodcasts)
        // Re-fetch saved/starred episodes so stars set from Home/Search/Trending
        // (outside the Library tab) surface on return. Throttled because a
        // quick out-and-back would otherwise refetch both sections twice.
        guard shouldRefreshSections else { return }
        await viewModel.refreshSavedEpisodes()
        await viewModel.refreshDownloadedEpisodes()
      }
    }
    .task {
      // Modernized notification observers using async sequences
      for await _ in NotificationCenter.default.notifications(named: .podcastSyncCompleted) {
        viewModel.refreshData()
        // BackgroundSyncManager writes through its own ModelContext, so the
        // grid would otherwise have to wait on the cross-context merge to
        // notice a show moved. Bumping a @State counter re-runs the signature
        // check against the current @Query results; unchanged = no-op.
        syncTick &+= 1
      }
    }
    .onChange(of: syncTick) { _, _ in
      applyPodcastsIfChanged(subscribedPodcasts)
    }
    // Watch the recency *signature*, not the array. `[PodcastInfoModel]`
    // equality is persistent-identity based, so `onChange(of: subscribedPodcasts)`
    // never fired when a sync only mutated `lastUpdated` / `latestEpisodeDate`
    // on shows already in the list — the grid then kept its old order until the
    // user left and re-entered the tab. Reading those two properties here also
    // registers the Observation dependency that invalidates this body when a
    // background-context sync merges in.
    //
    // No withAnimation here: animating a full grid map+sort+dictionary
    // rebuild was both a main-thread cost and visible jank. The grid items
    // are cheap value types; LibraryPodcastsGrid animates the reposition.
    .onChange(of: visibleRecencySignature) { _, _ in
      guard isVisible else { return }
      applyPodcastsIfChanged(subscribedPodcasts)
    }
    // Pushing a NavigationLink fires this, which is exactly what we want: it
    // parks the @Query for as long as a sub-page is on top. `onAppear` re-syncs
    // on the way back.
    .onDisappear { isVisible = false }

    // Note: Do NOT call viewModel.cleanup() here — LibraryView is a tab root,
    // and pushing a NavigationLink fires onDisappear.  Cleaning up would cancel
    // the download-completion observer while the user is in a sub-page.
    .alert(
      "Error",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
  }

  // MARK: - Helper Methods

  /// Order-and-content signature of the current snapshot. Includes
  /// `latestEpisodeDate` — the value the grid actually sorts on — because a
  /// feed refresh started from EpisodeListView updates it without touching
  /// `lastUpdated`, and a legacy-row backfill updates it deliberately without
  /// bumping the sync timestamp.
  private var podcastRecencySignature: Int {
    signature(for: subscribedPodcasts)
  }

  /// The recency signature, but only while this tab is actually on screen.
  ///
  /// Reading `subscribedPodcasts` runs the `@Query`'s fetch synchronously inside
  /// `body` — Instruments (`library-timeprofile-0829.trace`) shows
  /// `LibraryView.subscribedPodcasts.getter` → `NSManagedObjectContext.fetch` →
  /// `sqlite3_step` at 3,767 ms, 22% of all main-thread CPU and 86% of the CPU
  /// inside `LibraryView.body`. Because this view is the NavigationStack root it
  /// stays alive under a pushed EpisodeListView, and every SwiftData write that
  /// screen makes re-invalidates the query: 73 of 96 body passes in the trace
  /// ran behind a screen the user could not see, and both the push and the pop
  /// hung on it.
  ///
  /// Off-screen the read is skipped entirely, so the query never runs. `onAppear`
  /// calls `applyPodcastsIfChanged` on the way back, which is what caught up the
  /// grid before this gate existed too.
  private var visibleRecencySignature: Int {
    isVisible ? podcastRecencySignature : 0
  }

  private func signature(for podcasts: [PodcastInfoModel]) -> Int {
    var hasher = Hasher()
    for podcast in podcasts {
      hasher.combine(podcast.id)
      hasher.combine(podcast.lastUpdated)
      hasher.combine(podcast.latestEpisodeDate)
    }
    return hasher.finalize()
  }

  /// Apply a new subscribed-podcasts snapshot only if its recency signature
  /// actually changed. Cheap check that skips the expensive map+sort, the
  /// dictionary rebuild, and the viewModel refresh on every body re-eval.
  private func applyPodcastsIfChanged(_ podcasts: [PodcastInfoModel]) {
    let currentSignature = signature(for: podcasts)
    guard currentSignature != lastProcessedSignature else { return }
    lastProcessedSignature = currentSignature
    podcastModelByID = Dictionary(uniqueKeysWithValues: podcasts.map { ($0.id, $0) })
    viewModel.setPodcasts(podcasts)

    // Build grid items, reusing the cached item whenever a podcast's
    // (id, lastUpdated) signature is unchanged. `PodcastGridItem(from:)` decodes
    // the SwiftData `podcastInfo` Codable blob AND scans the full episode array
    // for the latest pubDate — doing that for every podcast on the main thread,
    // on every Library appearance / SwiftData write, was the source of the
    // navigation hangs (Instruments: LibraryView.body up to ~280 ms/eval).
    // Caching means we pay that cost only for podcasts that actually changed.
    var rebuiltCache: [PodcastInfoModel.ID: CachedGridItem] = [:]
    rebuiltCache.reserveCapacity(podcasts.count)
    let items: [PodcastGridItem] = podcasts.map { model in
      let stamp = CachedGridItem.Stamp(model)
      if let cached = gridItemCache[model.id], cached.stamp == stamp {
        rebuiltCache[model.id] = cached
        return cached.item
      }
      let item = PodcastGridItem(from: model)
      rebuiltCache[model.id] = CachedGridItem(stamp: stamp, item: item)
      return item
    }
    gridItemCache = rebuiltCache

    sortedPodcasts = items.sorted {
      PodcastRecencyOrder.isOrderedBefore(
        $0.latestEpisodeDate, $0.title, $1.latestEpisodeDate, $1.title)
    }
  }

}

/// A `PodcastGridItem` tagged with the recency stamp it was built from, so
/// `LibraryView` can reuse it across appearances without re-decoding the
/// podcast's `podcastInfo` blob when nothing changed.
private struct CachedGridItem {
  /// Both fields, not just `lastUpdated`: a refresh started from
  /// EpisodeListView moves `latestEpisodeDate` on its own, and stamping only
  /// on the sync timestamp served a stale cached cell for that show.
  struct Stamp: Equatable {
    let lastUpdated: Date
    let latestEpisodeDate: Date?

    init(_ model: PodcastInfoModel) {
      self.lastUpdated = model.lastUpdated
      self.latestEpisodeDate = model.latestEpisodeDate
    }
  }

  let stamp: Stamp
  let item: PodcastGridItem
}

// MARK: - Isolated transcript toolbar badge

/// Reads `TranscriptManager.shared.activeJobs` only inside this small view, so
/// the high-frequency progress updates re-render only the badge instead of
/// the whole Library screen.
private struct TranscriptToolbarBadge: View {
  @Binding var showSheet: Bool
  @State private var manager = TranscriptManager.shared

  var body: some View {
    let count = manager.activeJobCount
    if count > 0 {
      Button {
        showSheet = true
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "waveform.badge.plus")
          Text("\(count)")
            .font(.caption.monospacedDigit())
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
