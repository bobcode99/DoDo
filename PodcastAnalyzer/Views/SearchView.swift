//
//  SearchView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/23.
//

import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Main Search View

struct PodcastSearchView: View {
    @State private var viewModel = PodcastSearchViewModel()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.tabNavigationCoordinator) private var tabCoordinator
    @Query(filter: #Predicate<PodcastInfoModel> { $0.isSubscribed == true })
    private var subscribedPodcasts: [PodcastInfoModel]

    @State private var selectedTab: SearchTab = .applePodcasts
    @State private var searchText = ""
    @State private var searchPresented = false

    // Cached library filter results (updated only when searchText changes)
    @State private var filteredPodcasts: [PodcastInfoModel] = []
    @State private var filteredEpisodes: [(episode: PodcastEpisodeInfo, podcastTitle: String, podcastImageURL: String, podcastLanguage: String)] = []
    @State private var transcriptSearchVM = TranscriptSearchViewModel()
    @State private var subscribeTask: Task<Void, Never>?
    @State private var debounceTask: Task<Void, Never>?
    @State private var subscribeError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            tabSelector
                .padding(.horizontal, 16)
                .padding(.top, 8)

            // Search results
            switch selectedTab {
            case .transcripts:
                transcriptResultsView
            default:
                if searchText.isEmpty {
                    emptySearchView
                } else if selectedTab == .applePodcasts {
                    applePodcastsResultsView
                } else {
                    libraryResultsView
                }
            }

        }
        .navigationTitle("Search")
        .searchable(text: $searchText, isPresented: $searchPresented, prompt: searchPrompt)
        // Hide the keyboard when a tapped result pushes onto this tab's
        // NavigationPath. Deactivating the search presentation is the only
        // thing that reliably dismisses the search field's keyboard —
        // focus-state changes alone don't resign it mid-push. searchText is
        // untouched, so the results are still there on swipe-back.
        .onChange(of: tabCoordinator?.searchRouter.path.count ?? 0) { oldCount, newCount in
            if newCount > oldCount {
                dismissKeyboard()
            }
        }
        .onSubmit(of: .search) {
            if selectedTab == .applePodcasts {
                viewModel.searchText = searchText
                viewModel.performSearch()
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
            dismissKeyboard()
        }
        .alert("Subscription Failed", isPresented: Binding(get: { subscribeError != nil }, set: { if !$0 { subscribeError = nil } })) {
            Button("OK", role: .cancel) { subscribeError = nil }
        } message: {
            Text(subscribeError ?? "")
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

    // MARK: - Tab Selector

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(SearchTab.allCases, id: \.self) { tab in
                SearchTabButton(
                    title: tab.rawValue,
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
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            Text("Search for podcasts")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(selectedTab == .applePodcasts
                 ? "Find new podcasts to subscribe"
                 : "Search your subscribed podcasts and episodes")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Apple Podcasts Results

    private var applePodcastsResultsView: some View {
        Group {
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Searching...")
                    Spacer()
                }
            } else if viewModel.podcasts.isEmpty {
                VStack {
                    Spacer()
                    Text("No results found")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(viewModel.podcasts, id: \.collectionId) { podcast in
                        Button {
                            navigate(PodcastBrowseRoute(
                                podcastName: podcast.collectionName,
                                artworkURL: podcast.artworkUrl100 ?? "",
                                artistName: podcast.artistName,
                                collectionId: String(podcast.collectionId),
                                applePodcastURL: nil
                            ))
                        } label: {
                            HStack {
                                ApplePodcastRow(
                                    podcast: podcast,
                                    isSubscribed: isSubscribed(podcast),
                                    onSubscribe: { subscribeToPodcast(podcast) }
                                )
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)

            }
        }
    }

    // MARK: - Library Results

    private var libraryResultsView: some View {
        Group {
            if filteredPodcasts.isEmpty && filteredEpisodes.isEmpty {
                VStack {
                    Spacer()
                    Text("No results in your library")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List {
                    // Podcasts section
                    if !filteredPodcasts.isEmpty {
                        Section {
                            ForEach(filteredPodcasts) { podcastModel in
                                LibraryPodcastRow(podcastModel: podcastModel) {
                                    navigate(PodcastBrowseRoute(podcastModel: podcastModel))
                                }
                            }
                        }
                    }

                    // Episodes section
                    if !filteredEpisodes.isEmpty {
                        Section {
                            ForEach(filteredEpisodes, id: \.episode.id) { item in
                                LibraryEpisodeRow(
                                    episode: item.episode,
                                    podcastTitle: item.podcastTitle,
                                    podcastImageURL: item.podcastImageURL,
                                    podcastLanguage: item.podcastLanguage,
                                    onPlay: {
                                      playEpisode(item.episode, podcastTitle: item.podcastTitle, imageURL: item.podcastImageURL)
                                    },
                                    onOpen: {
                                        navigate(EpisodeDetailRoute(
                                            episode: item.episode,
                                            podcastTitle: item.podcastTitle,
                                            fallbackImageURL: item.podcastImageURL,
                                            podcastLanguage: item.podcastLanguage
                                        ))
                                    }
                                )
                            }
                        }
                    }
                }
                .listStyle(.plain)

            }
        }
    }

    // MARK: - Transcript Results

    private var transcriptResultsView: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Filter by Podcast", selection: $transcriptSearchVM.selectedPodcastFilter) {
                    Text("All Podcasts").tag(String?(nil))
                    ForEach(podcastTitles, id: \.self) { title in
                        Text(title).tag(String?(title))
                    }
                }
                .pickerStyle(.menu)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if searchText.isEmpty {
                Spacer()
                Image(systemName: "text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Search episode transcripts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                Spacer()
            } else if transcriptSearchVM.isSearching {
                Spacer()
                ProgressView()
                Spacer()
            } else if transcriptSearchVM.results.isEmpty {
                Spacer()
                Text("No transcript matches found")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(transcriptSearchVM.results) { result in
                        TranscriptResultRow(result: result)
                    }
                }
                .listStyle(.plain)

            }
        }
    }

    private var podcastTitles: [String] {
        subscribedPodcasts.map { $0.podcastInfo.title }.sorted()
    }

    private var searchPrompt: LocalizedStringKey {
        switch selectedTab {
        case .applePodcasts: "Search Apple Podcasts"
        case .library: "Search your library"
        case .transcripts: "Search transcripts"
        }
    }

    // MARK: - Helper Methods

    private func dismissKeyboard() {
        searchPresented = false
        #if os(iOS)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.endEditing(true)
            }
        }
        #endif
    }

    /// Dismisses the keyboard first, then pushes after a beat. The tab-bar
    /// search field (Tab role .search) orphans its keyboard if it is still
    /// first responder when a push starts — nothing can dismiss it afterwards.
    /// Resigning while the field is still frontmost works normally, so order
    /// matters: dismiss, let it land, then navigate.
    /// Pushes a result's route. When the tab-bar search field (Tab role
    /// .search) is active, the keyboard must be dismissed BEFORE the push:
    /// pushing while the field is first responder orphans the keyboard
    /// (nothing can dismiss it afterwards), and pushing during the search
    /// collapse animation gets silently dropped by the NavigationStack. So:
    /// dismiss, wait out the collapse, then push. Verified in simulator.
    private func navigate(_ route: any Hashable) {
        #if os(iOS)
        if searchPresented {
            dismissKeyboard()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                tabCoordinator?.searchRouter.push(route)
            }
        } else {
            tabCoordinator?.searchRouter.push(route)
        }
        #else
        tabCoordinator?.searchRouter.push(route)
        #endif
    }

    private func isSubscribed(_ podcast: Podcast) -> Bool {
        subscribedPodcasts.contains { $0.podcastInfo.title == podcast.collectionName }
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
                    existingByRSS.isSubscribed = true
                    existingByRSS.applyPodcastInfo(podcastInfo)
                    existingByRSS.lastUpdated = Date.now
                } else if let existingByTitle = try? modelContext.fetch(FetchDescriptor<PodcastInfoModel>(
                    predicate: #Predicate { $0.title == title }
                )).first {
                    existingByTitle.isSubscribed = true
                    existingByTitle.applyPodcastInfo(podcastInfo)
                    existingByTitle.lastUpdated = Date.now
                } else {
                    let podcastInfoModel = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date.now)
                    modelContext.insert(podcastInfoModel)
                    try? modelContext.save()
                    SubscriptionSyncCoordinator.shared.sync(from: podcastInfoModel)
                    return
                }

                try? modelContext.save()
            } catch {
                subscribeError = error.localizedDescription
            }
        }
    }

    private func playEpisode(_ episode: PodcastEpisodeInfo, podcastTitle: String, imageURL: String) {
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
            podcast.podcastInfo.title.localizedStandardContains(query)
        }

        var episodeResults: [(episode: PodcastEpisodeInfo, podcastTitle: String, podcastImageURL: String, podcastLanguage: String)] = []
        for podcast in subscribedPodcasts {
            let matchingEpisodes = podcast.podcastInfo.episodes.filter { episode in
                episode.title.localizedStandardContains(query) ||
                (episode.podcastEpisodeDescription?.localizedStandardContains(query) ?? false)
            }
            for episode in matchingEpisodes {
                episodeResults.append((
                    episode: episode,
                    podcastTitle: podcast.podcastInfo.title,
                    podcastImageURL: podcast.podcastInfo.imageURL,
                    podcastLanguage: podcast.podcastInfo.language
                ))
            }
        }
        filteredEpisodes = episodeResults
    }
}

// MARK: - Preview

#Preview {
    PodcastSearchView()
}
