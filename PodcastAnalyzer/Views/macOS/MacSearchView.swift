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
  @State private var viewModel = PodcastSearchViewModel()
  @Environment(\.modelContext) private var modelContext
  @Query(filter: #Predicate<PodcastInfoModel> { $0.isSubscribed == true })
  private var subscribedPodcasts: [PodcastInfoModel]

  @State private var selectedTab: SearchTab = .applePodcasts
  @State private var searchText = ""

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
          emptySearchView
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
    .onChange(of: searchText) { _, newValue in
      viewModel.searchText = newValue
      if selectedTab == .applePodcasts && !newValue.isEmpty {
        viewModel.performSearch()
      }
    }
    .onChange(of: selectedTab) { _, newTab in
      if newTab == .applePodcasts && !searchText.isEmpty {
        viewModel.searchText = searchText
        viewModel.performSearch()
      }
    }
  }

  // MARK: - Tab Selector

  private var tabSelector: some View {
    HStack(spacing: 0) {
      ForEach(SearchTab.allCases, id: \.self) { tab in
        Button(action: {
          withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = tab
          }
        }) {
          Text(tab.rawValue)
            .font(.subheadline)
            .fontWeight(selectedTab == tab ? .semibold : .regular)
            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
              RoundedRectangle(cornerRadius: 8)
                .fill(selectedTab == tab ? Color.gray.opacity(0.2) : Color.clear)
            )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(4)
    .background(Color.gray.opacity(0.1))
    .clipShape(.rect(cornerRadius: 10))
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
                onSubscribe: { subscribeToPodcast(podcast) }
              )
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
    let filteredPodcasts = filterLibraryPodcasts()
    let filteredEpisodes = filterLibraryEpisodes()

    return Group {
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
                NavigationLink(value: PodcastBrowseRoute(podcastModel: podcastModel)) {
                  MacLibraryPodcastRow(podcastModel: podcastModel)
                }
              }
            }
          }

          // Episodes section
          if !filteredEpisodes.isEmpty {
            Section {
              ForEach(filteredEpisodes, id: \.uniqueId) { item in
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

  // MARK: - Helper Methods

  private func isSubscribed(_ podcast: Podcast) -> Bool {
    subscribedPodcasts.contains { $0.title == podcast.collectionName }
  }

  private func subscribeToPodcast(_ podcast: Podcast) {
    guard let feedUrl = podcast.feedUrl else { return }

    Task {
      do {
        let rssService = PodcastRssService()
        let podcastInfo = try await rssService.fetchPodcast(from: feedUrl)
        let podcastInfoModel = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date.now)

        modelContext.insert(podcastInfoModel)
        modelContext.saveOrLog()
        SubscriptionSyncCoordinator.shared.sync(from: podcastInfoModel)
      } catch {
        logger.error("Failed to subscribe: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func filterLibraryPodcasts() -> [PodcastInfoModel] {
    let query = searchText
    return subscribedPodcasts.filter { podcast in
      podcast.title.localizedStandardContains(query)
    }
  }

  private func filterLibraryEpisodes() -> [(uniqueId: String, episode: PodcastEpisodeInfo, podcastTitle: String, podcastImageURL: String, podcastLanguage: String)] {
    let query = searchText
    var results: [(uniqueId: String, episode: PodcastEpisodeInfo, podcastTitle: String, podcastImageURL: String, podcastLanguage: String)] = []

    for podcast in subscribedPodcasts {
      // Bind the blob once per podcast — this runs per keystroke, and it was
      // being re-read four times for every match.
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
  let onSubscribe: () -> Void

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
      } else if isSubscribing {
        ProgressView()
          .scaleEffect(0.8)
      } else {
        Button(action: {
          isSubscribing = true
          onSubscribe()
          Task {
            try? await Task.sleep(for: .seconds(2))
            isSubscribing = false
          }
        }) {
          Image(systemName: "plus")
            .font(.title3)
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
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
