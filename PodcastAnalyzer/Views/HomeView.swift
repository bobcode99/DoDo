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
struct TrendingEpisodeDetailDestination: Hashable {
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
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private static let isoFormatterNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
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
  @State private var viewModel = HomeViewModel()
  @Environment(\.modelContext) private var modelContext
  @State private var showRegionPicker = false
  @State private var showNotificationInbox = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        UpNextSection(viewModel: viewModel)

        if #available(iOS 26.0, macOS 26.0, *) {
          ForYouSection(viewModel: viewModel)
        }

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
    }
    .navigationDestination(for: TrendingEpisodeDetailDestination.self) { dest in
      EpisodeDetailView(
        episode: dest.asPodcastEpisodeInfo,
        podcastTitle: dest.podcastName,
        fallbackImageURL: dest.podcastArtworkUrl
      )
    }
    .navigationDestination(for: TrendingEpisodesDestination.self) { _ in
      TrendingEpisodesListView(episodes: viewModel.trendingEpisodes)
    }
    .navigationDestination(for: PopularShowsDestination.self) { _ in
      PopularShowsListView(podcasts: viewModel.topPodcasts, viewModel: viewModel)
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
          Image(systemName: "bell")
            .overlay(alignment: .topTrailing) {
              if NotificationInbox.shared.unreadCount > 0 {
                Circle()
                  .fill(.red)
                  .frame(width: 8, height: 8)
                  .offset(x: 2, y: -2)
              }
            }
        }
        .accessibilityLabel("Notifications")
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
      await viewModel.refresh()
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

#Preview {
  HomeView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
