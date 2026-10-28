//
//  SearchView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/23.
//

import SwiftData
import SwiftUI

// MARK: - Main Search View

struct PodcastSearchView: View {
    @State private var viewModel = PodcastSearchViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tabNavigationCoordinator) private var tabCoordinator
    @Query(filter: #Predicate<PodcastInfoModel> { $0.isSubscribed == true })
    private var subscribedPodcasts: [PodcastInfoModel]

    @State private var selectedTab: SearchTab = .applePodcasts
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    // Cached library filter results (updated only when searchText changes)
    @State private var filteredPodcasts: [PodcastInfoModel] = []
    @State private var filteredEpisodes: [LibrarySearchEpisode] = []
    @State private var transcriptSearchVM = TranscriptSearchViewModel()
    @State private var subscribeTask: Task<Void, Never>?
    @State private var debounceTask: Task<Void, Never>?
    @State private var subscribeError: String?

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Tab selector
            tabSelector
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Search results
            switch selectedTab {
            case .transcripts:
                TranscriptSearchResultsView(
                    viewModel: transcriptSearchVM,
                    podcastTitles: podcastTitles,
                    isQueryEmpty: searchText.isEmpty
                )
            default:
                if searchText.isEmpty {
                    emptySearchView
                } else if selectedTab == .applePodcasts {
                    AppleSearchResultsView(
                        isLoading: viewModel.isLoading,
                        podcasts: viewModel.podcasts,
                        episodes: viewModel.episodes,
                        isSubscribed: isSubscribed,
                        onSubscribe: subscribeToPodcast,
                        onNavigate: navigate
                    )
                } else {
                    LibrarySearchResultsView(
                        podcasts: filteredPodcasts,
                        episodes: filteredEpisodes,
                        onNavigate: navigate,
                        onPlay: playEpisode
                    )
                }
            }

        }
        .navigationTitle("Search")
        .platformToolbarTitleDisplayMode()
        // Registered here, not in navigationDestinations(): Home registers its
        // own with a zoom transition, and a stack must not see two handlers.
        .navigationDestination(for: TrendingEpisodeDetailDestination.self) { dest in
            EpisodeDetailView(
                episode: dest.asPodcastEpisodeInfo,
                podcastTitle: dest.podcastName,
                fallbackImageURL: dest.podcastArtworkUrl
            )
        }
        // Hide the keyboard when a tapped result pushes onto this tab's
        // NavigationPath. searchText is untouched, so the results are still
        // there on swipe-back.
        .onChange(of: tabCoordinator?.searchRouter.path.count ?? 0) { oldCount, newCount in
            if newCount > oldCount {
                isSearchFocused = false
            }
        }
        .task(id: TranscriptSearchKey(tab: selectedTab, query: searchText)) {
            guard selectedTab == .transcripts, !searchText.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await transcriptSearchVM.performSearch(query: searchText, podcasts: subscribedPodcasts)
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
            if selectedTab == .transcripts {
                // task(id:) handles transcript search re-trigger on text change
            } else {
                // Debounce: wait before firing search/filter to avoid lag on every keystroke
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    if selectedTab == .applePodcasts && !newValue.isEmpty {
                        viewModel.performSearch()
                    }
                    if selectedTab == .library {
                        updateLibraryFilters()
                    }
                }
            }
        }
        .onDisappear {
            subscribeTask?.cancel()
            debounceTask?.cancel()
            isSearchFocused = false
        }
        .alert("Subscription Failed", item: $subscribeError) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error)
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .applePodcasts && !searchText.isEmpty {
                viewModel.searchText = searchText
                viewModel.performSearch()
            } else if newTab == .library {
                updateLibraryFilters()
            } else if newTab == .transcripts {
                // task(id:) handles re-trigger when switching to this tab
            }
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        SearchField(text: $searchText, prompt: searchPrompt, isFocused: $isSearchFocused, onSubmit: submitSearch)
    }

    private func submitSearch() {
        if selectedTab == .applePodcasts {
            viewModel.searchText = searchText
            viewModel.performSearch()
        }
    }

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(SearchTab.allCases, id: \.self) { tab in
                SearchTabButton(
                    title: tab.title,
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(4)
        .glassEffect(Glass.regular, in: .rect(cornerRadius: 10))
    }

    // MARK: - Empty Search View

    private var emptySearchView: some View {
        ContentUnavailableView(
            "Search for podcasts",
            systemImage: "magnifyingglass",
            description: Text(selectedTab == .applePodcasts
                ? "Find new podcasts to subscribe"
                : "Search your subscribed podcasts and episodes")
        )
    }

    private var podcastTitles: [String] {
        subscribedPodcasts.map(\.title).sorted()
    }

    private var searchPrompt: LocalizedStringKey {
        switch selectedTab {
        case .applePodcasts: "Search all podcasts"
        case .library: "Search your library"
        case .transcripts: "Search transcripts"
        }
    }

    // MARK: - Helper Methods

    private func navigate(_ route: any Hashable) {
        isSearchFocused = false
        tabCoordinator?.searchRouter.push(route)
    }

    private func isSubscribed(_ podcast: Podcast) -> Bool {
        subscribedPodcasts.contains { $0.title == podcast.collectionName }
    }

    private func subscribeToPodcast(_ podcast: Podcast) {
        guard let feedUrl = podcast.feedUrl else { return }

        subscribeTask?.cancel()
        subscribeTask = Task {
            do {
                let rssService = PodcastRssService()
                let podcastInfo = try await rssService.fetchPodcast(from: feedUrl)
                let title = podcastInfo.title
                if let existingByRSS = try? modelContext.fetch(FetchDescriptor<PodcastInfoModel>(
                    predicate: #Predicate { $0.rssUrl == feedUrl }
                )).first {
                    existingByRSS.setSubscribed(true)
                    existingByRSS.applyPodcastInfo(podcastInfo)
                    existingByRSS.lastUpdated = Date.now
                } else if let existingByTitle = try? modelContext.fetch(FetchDescriptor<PodcastInfoModel>(
                    predicate: #Predicate { $0.title == title }
                )).first {
                    existingByTitle.setSubscribed(true)
                    existingByTitle.applyPodcastInfo(podcastInfo)
                    existingByTitle.lastUpdated = Date.now
                } else {
                    let podcastInfoModel = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date.now)
                    modelContext.insert(podcastInfoModel)
                    try modelContext.save()
                    SubscriptionSyncCoordinator.shared.sync(from: podcastInfoModel)
                    return
                }

                try modelContext.save()
            } catch {
                subscribeError = error.localizedDescription
            }
        }
    }

    private func playEpisode(_ item: LibrarySearchEpisode) {
        let episode = item.episode
        let podcastTitle = item.podcastTitle
        let imageURL = item.podcastImageURL
        guard let audioURL = episode.audioURL else { return }
        let playbackEpisode = PlaybackEpisode(
            id: "\(podcastTitle)\u{1F}\(episode.title)",
            title: episode.title,
            podcastTitle: podcastTitle,
            audioURL: audioURL,
            imageURL: episode.imageURL ?? imageURL,
            episodeDescription: episode.podcastEpisodeDescription,
            pubDate: episode.pubDate,
            duration: episode.duration,
            guid: episode.guid
        )
        EnhancedAudioManager.shared.play(
            episode: playbackEpisode,
            audioURL: audioURL,
            startTime: 0,
            imageURL: episode.imageURL ?? imageURL,
            useDefaultSpeed: true
        )
    }

    private func updateLibraryFilters() {
        let query = searchText
        guard !query.isEmpty else {
            filteredPodcasts = []
            filteredEpisodes = []
            return
        }

        filteredPodcasts = subscribedPodcasts.filter { podcast in
            podcast.title.localizedStandardContains(query)
        }

        filteredEpisodes = LibrarySearchFilter.episodes(
            in: subscribedPodcasts.map(\.podcastInfo),
            matching: query
        )
    }
}

// MARK: - Preview

#Preview {
    PodcastSearchView()
}
