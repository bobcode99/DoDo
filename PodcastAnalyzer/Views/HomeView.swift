//
//  HomeView.swift
//  PodcastAnalyzer
//
//  Home tab - shows Up Next (unplayed episodes) and Popular Shows from Apple Podcasts
//

import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#endif

// Navigation destination types for See All pages
struct TrendingEpisodesDestination: Hashable {}
struct PopularShowsDestination: Hashable {}

/// Destination for navigating to a trending episode's detail view
struct TrendingEpisodeDetailDestination: Hashable, Identifiable {
  /// Same shape as `ApplePodcastService.TrendingEpisode.id`, and stable across
  /// accesses — it is what the zoom transition matches the source card on.
  var id: String { "\(podcastId)\u{1F}\(episodeTitle)" }

  let episodeTitle: String
  let episodeDescription: String?
  let releaseDate: String?
  let audioURL: String?
  let durationMillis: Int?
  let artworkUrl: String?
  let podcastName: String
  let podcastArtworkUrl: String?
  let podcastId: String

  init(from trending: ApplePodcastService.TrendingEpisode) {
    self.episodeTitle = trending.episode.trackName
    self.episodeDescription = trending.episode.description ?? trending.episode.shortDescription
    self.releaseDate = trending.episode.releaseDate
    self.audioURL = trending.episode.episodeUrl ?? trending.episode.previewUrl
    self.durationMillis = trending.episode.trackTimeMillis
    self.artworkUrl = trending.episode.artworkUrl600 ?? trending.episode.artworkUrl160
    self.podcastName = trending.podcastName
    self.podcastArtworkUrl = trending.podcastArtworkUrl
    self.podcastId = trending.podcastId
  }

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let isoFormatterNoFrac: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  /// Convert to PodcastEpisodeInfo for EpisodeDetailView
  var asPodcastEpisodeInfo: PodcastEpisodeInfo {
    var pubDate: Date?
    if let dateStr = releaseDate {
      pubDate = Self.isoFormatter.date(from: dateStr)
              ?? Self.isoFormatterNoFrac.date(from: dateStr)
    }

    return PodcastEpisodeInfo(
      title: episodeTitle,
      podcastEpisodeDescription: episodeDescription,
      pubDate: pubDate,
      audioURL: audioURL,
      imageURL: artworkUrl ?? podcastArtworkUrl,
      duration: durationMillis.map { $0 / 1000 }
    )
  }
}

struct HomeView: View {
  /// Owned here, apart from `HomeScreen`, so the `@State` initial expression runs
  /// once: `HomeView()` is rebuilt on every `ContentView` update, and a model
  /// built in `init` did its disk reads each time before SwiftUI discarded it.
  @State private var viewModel = HomeViewModel()

  var body: some View {
    HomeScreen(viewModel: viewModel)
  }
}

/// `viewModel` is a parameter so previews can seed Up Next / Popular Shows /
/// Top Episodes into their populated, empty, and loading states without a
/// network or model context.
struct HomeScreen: View {
  @Bindable var viewModel: HomeViewModel
  @Environment(\.modelContext) private var modelContext
  @State private var showRegionPicker = false
  @State private var showNotificationInbox = false
  @Environment(\.zoomNamespace) private var zoomNamespace

  private var unreadCount: Int { NotificationInbox.shared.unreadCount }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        UpNextSection(viewModel: viewModel)

        TrendingEpisodesSection(viewModel: viewModel)

        PopularShowsSection(viewModel: viewModel)
      }
      .padding(.vertical)
    }
    .navigationDestination(for: UpNextListRoute.self) { _ in
      // Bind to the live VM array (not the route's frozen snapshot) so
      // dismiss / play / completion updates immediately reflect on this page.
      UpNextListView(
        episodes: viewModel.upNextEpisodes,
        onToggleStar: { viewModel.toggleStar(for: $0) },
        onTogglePlayed: { viewModel.togglePlayed(for: $0) },
        onDownload: {
          DownloadManager.shared.downloadEpisode(
            episode: $0.episodeInfo,
            podcastTitle: $0.podcastTitle,
            language: $0.language
          )
        },
        onDeleteDownload: {
          DownloadManager.shared.deleteDownload(
            episodeTitle: $0.episodeInfo.title,
            podcastTitle: $0.podcastTitle
          )
        },
        onDismiss: { viewModel.dismissFromUpNext($0) }
      )
    }
    .navigationDestination(for: AppleRSSPodcast.self) { podcast in
      EpisodeListView(
        podcastName: podcast.name,
        podcastArtwork: podcast.safeArtworkUrl,
        artistName: podcast.artistName,
        collectionId: podcast.id,
        applePodcastUrl: podcast.url
      )
      .zoomDestination(id: podcast.id, in: zoomNamespace)
    }
    .navigationDestination(for: TrendingEpisodeDetailDestination.self) { dest in
      EpisodeDetailView(
        episode: dest.asPodcastEpisodeInfo,
        podcastTitle: dest.podcastName,
        fallbackImageURL: dest.podcastArtworkUrl
      )
      .zoomDestination(id: dest.id, in: zoomNamespace)
    }
    .navigationDestination(for: TrendingEpisodesDestination.self) { _ in
      TrendingEpisodesListView(episodes: viewModel.trendingEpisodes)
    }
    .navigationDestination(for: PopularShowsDestination.self) { _ in
      PopularShowsListView(viewModel: viewModel)
    }
    .navigationTitle(Constants.homeString)
    .platformToolbarTitleDisplayMode()
    .toolbar {
      ToolbarItem(placement: .navigation) {
        SyncProgressToolbarBadge()
      }
      ToolbarItem(placement: .primaryAction) {
        Button {
          showNotificationInbox = true
        } label: {
          Label("Notifications", systemImage: "bell")
            .labelStyle(.iconOnly)
            .overlay(alignment: .topTrailing) {
              if unreadCount > 0 {
                Circle()
                  .fill(.red)
                  .frame(width: 8, height: 8)
                  .offset(x: 2, y: -2)
              }
            }
        }
        .accessibilityValue(unreadCount > 0 ? Text("\(unreadCount) unread") : Text(verbatim: ""))
      }
      ToolbarItem(placement: .primaryAction) {
        Button(action: { showRegionPicker = true }) {
          HStack(spacing: 4) {
            Text(viewModel.selectedRegionFlag)
              .font(.title3)
            Image(systemName: "chevron.down")
              .font(.caption2)
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .glassEffect(Glass.regular.interactive(), in: .rect(cornerRadius: 12))
        }
        .accessibilityLabel("Change region")
        .accessibilityValue(viewModel.selectedStorefront.name)
      }
    }
    .sheet(isPresented: $showNotificationInbox) {
      NotificationInboxView()
    }
    .sheet(isPresented: $showRegionPicker) {
      RegionPickerSheet(
        selectedRegion: $viewModel.selectedRegion,
        isPresented: $showRegionPicker
      )
      .presentationDetents([.medium])
    }
    .refreshable {
      // Don't hold the spinner for the network (Apple's chart API can hang
      // ~30s): while it shows, iOS 27 draws the content ~60pt lower than it
      // hit-tests, so a tap on a row opens the one below. Each section shows its
      // own loading indicator instead. Unstructured, so a re-render mid-refresh
      // can't cancel it either.
      Task { await viewModel.refresh() }
    }
    .onAppear {
      // This is the key: set the context once
      viewModel.setModelContext(modelContext)
    }
    .onDisappear {
      // Cleanup region observer task to prevent memory leaks
      viewModel.cleanup()
    }
  }

}

// MARK: - Preview Mocks

/// Builds a `HomeViewModel` and overwrites its data arrays directly — every
/// property below is a plain `var`, so no model context or network call is
/// needed to drive the three sections through their different states.
private func mockHomeViewModel(
  upNext: [ScoredEpisode] = [],
  popularShows: [AppleRSSPodcast] = [],
  trending: [ApplePodcastService.TrendingEpisode] = [],
  isLoadingPopularShows: Bool = false,
  isLoadingTrending: Bool = false,
  popularShowsFetchedAt: Date? = nil
) -> HomeViewModel {
  let vm = HomeViewModel()
  vm.upNextEpisodes = upNext.map(\.episode)
  vm.scoredUpNextEpisodes = upNext
  vm.topPodcasts = popularShows
  vm.trendingEpisodes = trending
  vm.isLoadingTopPodcasts = isLoadingPopularShows
  vm.isLoadingTrendingEpisodes = isLoadingTrending
  vm.popularShowsFetchedAt = popularShowsFetchedAt
  return vm
}

private func mockScoredEpisode(
  title: String,
  podcast: String,
  reason: SuggestionReason,
  progressRatio: Double = 0
) -> ScoredEpisode {
  let episode = LibraryEpisode(
    id: "\(podcast)\u{1F}\(title)",
    podcastTitle: podcast,
    imageURL: nil,
    language: "en",
    episodeInfo: PodcastEpisodeInfo(
      title: title,
      podcastEpisodeDescription: "A deep dive into the topic of the week.",
      pubDate: Date.now,
      audioURL: "https://example.com/\(title).mp3",
      duration: 1800
    ),
    isStarred: reason == .starred,
    isDownloaded: reason == .downloaded,
    isCompleted: false,
    lastPlaybackPosition: progressRatio > 0 ? 1800 * progressRatio : 0,
    savedDuration: 1800
  )
  return ScoredEpisode(episode: episode, downloadModel: nil, score: 1, reason: reason, progressRatio: progressRatio)
}

private func mockPodcast(id: String, name: String) -> AppleRSSPodcast {
  AppleRSSPodcast(
    id: id,
    artistName: "\(name) Media",
    name: name,
    artworkUrl100: nil,
    url: "https://podcasts.apple.com/podcast/id\(id)",
    genres: nil,
    contentAdvisoryRating: nil,
    releaseDate: nil,
    kind: nil
  )
}

private func mockTrendingEpisode(title: String, podcast: String, podcastId: String) -> ApplePodcastService.TrendingEpisode {
  ApplePodcastService.TrendingEpisode(
    id: "\(podcastId)_\(title)",
    podcastName: podcast,
    podcastArtworkUrl: nil,
    podcastId: podcastId,
    episode: Episode(
      wrapperType: "podcastEpisode",
      kind: "podcast-episode",
      trackId: nil,
      trackName: title,
      description: "Trending episode preview description.",
      shortDescription: nil,
      releaseDate: nil,
      trackTimeMillis: 1_800_000,
      contentAdvisoryRating: nil,
      trackViewUrl: nil,
      previewUrl: nil,
      episodeUrl: "https://example.com/\(title).mp3",
      artworkUrl600: nil,
      artworkUrl160: nil,
      country: nil,
      language: nil,
      genres: nil,
      collectionId: nil,
      collectionName: nil,
      episodeGuid: nil,
      closedCaptioning: nil,
      episodeContentType: nil,
      episodeFileExtension: nil
    )
  )
}

private let mockUpNext: [ScoredEpisode] = [
  mockScoredEpisode(title: "The 45-Minute Rule", podcast: "The Daily", reason: .inQueue(position: 1)),
  mockScoredEpisode(title: "Think Baseball Is Boring? The Sabermetrics Revolution", podcast: "Freakonomics Radio", reason: .inProgress, progressRatio: 0.32),
  mockScoredEpisode(title: "Understanding Swift Concurrency in Practice", podcast: "The Swift Podcast", reason: .newEpisode),
  mockScoredEpisode(title: "A Deep Dive Into Ambient Sound Design", podcast: "20,000 Hertz", reason: .downloaded),
]

private let mockPopularShows: [AppleRSSPodcast] = [
  mockPodcast(id: "1", name: "The Daily"),
  mockPodcast(id: "2", name: "Freakonomics Radio"),
  mockPodcast(id: "3", name: "The Swift Podcast"),
  mockPodcast(id: "4", name: "20,000 Hertz"),
  mockPodcast(id: "5", name: "Radiolab"),
]

private let mockTrending: [ApplePodcastService.TrendingEpisode] = [
  mockTrendingEpisode(title: "Season Finale: What We Got Wrong", podcast: "The Daily", podcastId: "1"),
  mockTrendingEpisode(title: "The Economics of Airport Food", podcast: "Freakonomics Radio", podcastId: "2"),
]

#Preview("Populated") {
  NavigationStack {
    HomeScreen(viewModel: mockHomeViewModel(
      upNext: mockUpNext,
      popularShows: mockPopularShows,
      trending: mockTrending,
      popularShowsFetchedAt: Date.now
    ))
  }
  .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}

#Preview("Up Next Empty") {
  NavigationStack {
    HomeScreen(viewModel: mockHomeViewModel(
      popularShows: mockPopularShows,
      trending: mockTrending,
      popularShowsFetchedAt: Date.now
    ))
  }
  .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}

#Preview("Popular Shows Empty") {
  NavigationStack {
    HomeScreen(viewModel: mockHomeViewModel(upNext: mockUpNext))
  }
  .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}

#Preview("Loading") {
  NavigationStack {
    HomeScreen(viewModel: mockHomeViewModel(
      upNext: mockUpNext,
      isLoadingPopularShows: true,
      isLoadingTrending: true
    ))
  }
  .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}

#Preview("New User — Nothing Yet") {
  NavigationStack {
    HomeScreen(viewModel: mockHomeViewModel())
  }
  .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
