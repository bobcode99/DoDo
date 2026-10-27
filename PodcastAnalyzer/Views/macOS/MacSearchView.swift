//
//  MacSearchView.swift
//  PodcastAnalyzer
//
//  macOS Search view — Apple Podcasts and library search
//

#if os(macOS)
import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "MacSearchView")

struct MacSearchView: View {
  private typealias LibraryEpisodeMatch = (
    uniqueId: String, episode: PodcastEpisodeInfo, podcastTitle: String, podcastImageURL: String, podcastLanguage: String
  )

  @State private var viewModel = PodcastSearchViewModel()
  @Environment(\.modelContext) private var modelContext
  @Query(filter: #Predicate<PodcastInfoModel> { $0.isSubscribed == true })
  private var subscribedPodcasts: [PodcastInfoModel]

  @State private var selectedTab: SearchTab = .applePodcasts
  @State private var searchText = ""
  @State private var libraryEpisodes: [LibraryEpisodeMatch] = []
  @State private var transcriptSearchVM = TranscriptSearchViewModel()
  @State private var subscribeError: String?

  var body: some View {
    VStack(spacing: 0) {
      // Tab selector
      tabSelector
        .padding(.horizontal, 16)
        .padding(.top, 8)

      // Search results
      if searchText.isEmpty {
        emptySearchView
      } else {
        switch selectedTab {
        case .applePodcasts:
          applePodcastsResultsView
        case .library:
          libraryResultsView
        case .transcripts:
          transcriptResultsView
        }
      }
    }
    .navigationTitle("Search")
    .searchable(text: $searchText, prompt: "Podcasts & Episodes")
    .onSubmit(of: .search) {
      if selectedTab == .applePodcasts {
        viewModel.searchText = searchText
        viewModel.performSearch()
      }
    }
    .task(id: [selectedTab.rawValue, searchText]) {
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      await runSearch()
    }
    .alert("Subscription Failed", item: $subscribeError) { _ in
      Button("OK", role: .cancel) {}
    } message: { error in
      Text(error)
    }
  }

  // MARK: - Tab Selector

  private var tabSelector: some View {
    Picker("Search In", selection: $selectedTab) {
      ForEach(SearchTab.allCases, id: \.self) { tab in
        Text(tab.title).tag(tab)
      }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
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
      } else if viewModel.podcasts.isEmpty && viewModel.episodes.isEmpty {
        // Named here and nowhere else — see the iOS view. Before a search the
        // directory is trivia; the moment a show is missing it is both the
        // explanation and the way out.
        VStack(spacing: 8) {
          Spacer()
          Text("No results found")
            .foregroundStyle(.secondary)
          Text("Search covers the Apple Podcasts directory. If a show isn't listed there, add it by RSS URL in Settings ▸ Subscriptions.")
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
          Spacer()
        }
      } else {
        List {
          if !viewModel.podcasts.isEmpty {
            Section("Shows") {
              ForEach(viewModel.podcasts, id: \.collectionId) { podcast in
                NavigationLink(
                  value: PodcastBrowseRoute(
                    podcastName: podcast.collectionName,
                    artworkURL: podcast.artworkUrl100 ?? "",
                    artistName: podcast.artistName,
                    collectionId: String(podcast.collectionId),
                    applePodcastURL: nil
                  )
                ) {
                  MacApplePodcastRow(
                    podcast: podcast,
                    isSubscribed: isSubscribed(podcast),
                    onSubscribe: { await subscribeToPodcast(podcast) }
                  )
                }
                .buttonStyle(.plain)
              }
            }
          }

          if !viewModel.episodes.isEmpty {
            Section("Episodes") {
              ForEach(viewModel.episodes, id: \.episode.id) { episode in
                NavigationLink(value: TrendingEpisodeDetailDestination(from: episode)) {
                  TrendingEpisodeRow(episode: episode, rank: nil)
                }
                .buttonStyle(.plain)
                .contextMenu {
                  TrendingEpisodeContextMenu(episode: episode)
                }
              }
            }
          }
        }
        .listStyle(.plain)
      }
    }
  }

  // MARK: - Library Results

  private var libraryResultsView: some View {
    let filteredPodcasts = filterLibraryPodcasts()

    return Group {
      if filteredPodcasts.isEmpty && libraryEpisodes.isEmpty {
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
                NavigationLink(value: PodcastBrowseRoute(podcastModel: podcastModel)) {
                  MacLibraryPodcastRow(podcastModel: podcastModel)
                }
              }
            }
          }

          // Episodes section
          if !libraryEpisodes.isEmpty {
            Section {
              ForEach(libraryEpisodes, id: \.uniqueId) { item in
                NavigationLink(value: EpisodeDetailRoute(
                  episode: item.episode,
                  podcastTitle: item.podcastTitle,
                  fallbackImageURL: item.podcastImageURL,
                  podcastLanguage: item.podcastLanguage
                )) {
                  MacLibraryEpisodeRow(
                    episode: item.episode,
                    podcastTitle: item.podcastTitle,
                    podcastImageURL: item.podcastImageURL,
                    podcastLanguage: item.podcastLanguage
                  )
                }
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
    Group {
      if transcriptSearchVM.isSearching {
        VStack {
          Spacer()
          ProgressView()
          Spacer()
        }
      } else if transcriptSearchVM.results.isEmpty {
        VStack {
          Spacer()
          Text("No transcript matches found")
            .foregroundStyle(.secondary)
          Spacer()
        }
      } else {
        List(transcriptSearchVM.results) { result in
          TranscriptResultRow(result: result)
        }
        .listStyle(.plain)
      }
    }
  }

  // MARK: - Helper Methods

  /// Library matching reads each show's episode blob, which SwiftData decodes
  /// on every access, so it runs here once per settled query instead of in body.
  private func runSearch() async {
    guard !searchText.isEmpty else { return }
    switch selectedTab {
    case .applePodcasts:
      viewModel.searchText = searchText
      viewModel.performSearch()
    case .library:
      libraryEpisodes = filterLibraryEpisodes()
    case .transcripts:
      await transcriptSearchVM.performSearch(query: searchText, podcasts: subscribedPodcasts)
    }
  }

  private func isSubscribed(_ podcast: Podcast) -> Bool {
    subscribedPodcasts.contains { $0.title == podcast.collectionName }
  }

  private func subscribeToPodcast(_ podcast: Podcast) async {
    guard let feedUrl = podcast.feedUrl else { return }

    do {
      let rssService = PodcastRssService()
      let podcastInfo = try await rssService.fetchPodcast(from: feedUrl)
      let podcastInfoModel = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date.now)

      modelContext.insert(podcastInfoModel)
      modelContext.saveOrLog()
      SubscriptionSyncCoordinator.shared.sync(from: podcastInfoModel)
    } catch {
      logger.error("Failed to subscribe: \(error.localizedDescription, privacy: .public)")
      subscribeError = error.localizedDescription
    }
  }

  private func filterLibraryPodcasts() -> [PodcastInfoModel] {
    let query = searchText
    return subscribedPodcasts.filter { podcast in
      podcast.title.localizedStandardContains(query)
    }
  }

  private func filterLibraryEpisodes() -> [LibraryEpisodeMatch] {
    let query = searchText
    var results: [LibraryEpisodeMatch] = []

    for podcast in subscribedPodcasts {
      // Bind the blob once per podcast; it was being re-read four times for
      // every match.
      let info = podcast.podcastInfo
      let matchingEpisodes = info.episodes.filter { episode in
        episode.title.localizedStandardContains(query) ||
        (episode.podcastEpisodeDescription?.localizedStandardContains(query) ?? false)
      }

      for episode in matchingEpisodes {
        let uniqueId = "\(info.title)\u{1F}\(episode.title)"
        results.append((
          uniqueId: uniqueId,
          episode: episode,
          podcastTitle: info.title,
          podcastImageURL: info.imageURL,
          podcastLanguage: info.language
        ))
      }
    }

    return results
  }
}

// MARK: - Apple Podcast Row

struct MacApplePodcastRow: View {
  let podcast: Podcast
  let isSubscribed: Bool
  let onSubscribe: () async -> Void

  @State private var isSubscribing = false

  var body: some View {
    HStack(spacing: 12) {
      CachedArtworkImage(urlString: podcast.artworkUrl100, size: 56, cornerRadius: 8)

      VStack(alignment: .leading, spacing: 2) {
        Text(podcast.collectionName)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)
          .foregroundStyle(.primary)

        Text("Show · \(podcast.artistName)")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      if isSubscribed {
        Image(systemName: "checkmark")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(.green)
          .accessibilityLabel("Subscribed")
      } else if isSubscribing {
        ProgressView()
          .controlSize(.small)
      } else {
        Button("Subscribe", systemImage: "plus") {
          isSubscribing = true
          Task {
            await onSubscribe()
            isSubscribing = false
          }
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .foregroundStyle(.blue)
        .buttonStyle(.plain)
        .help("Subscribe")
      }

      Image(systemName: "chevron.right")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }
}

#endif
