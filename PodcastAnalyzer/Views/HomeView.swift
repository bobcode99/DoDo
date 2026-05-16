//
//  HomeView.swift
//  PodcastAnalyzer
//
//  Home tab - shows Up Next (unplayed episodes) and Popular Shows from Apple Podcasts
//

import NukeUI
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
  @State private var syncManager = BackgroundSyncManager.shared
  @Environment(\.modelContext) private var modelContext
  @State private var showRegionPicker = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        // Up Next Section
        upNextSection

        // For You Section (on-device AI recommendations)
        if #available(iOS 26.0, macOS 26.0, *) {
          forYouSection
        }

        // Trending Episodes Section
        trendingEpisodesSection

        // Popular Shows Section
        popularShowsSection
      }
      .padding(.vertical)
    }
    .navigationDestination(for: UpNextListRoute.self) { route in
      UpNextListView(
        episodes: route.episodes,
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

  // MARK: - Up Next Context Menu Builder

  private func upNextContextMenu(for episode: LibraryEpisode) -> UpNextContextMenu {
    let checker = EpisodeStatusChecker(episode: episode)
    return UpNextContextMenu(
      episode: episode,
      isStarred: episode.isStarred,
      isCompleted: episode.isCompleted,
      downloadState: checker.downloadState,
      podcastModel: viewModel.findPodcastModel(for: episode.podcastTitle),
      onToggleStar: { viewModel.toggleStar(for: episode) },
      onTogglePlayed: { viewModel.togglePlayed(for: episode) },
      onPlayNext: {
        guard let audioURL = episode.episodeInfo.audioURL else { return }
        let playbackEpisode = PlaybackEpisode(
          id: episode.id,
          title: episode.episodeInfo.title,
          podcastTitle: episode.podcastTitle,
          audioURL: audioURL,
          imageURL: episode.imageURL,
          episodeDescription: episode.episodeInfo.podcastEpisodeDescription,
          pubDate: episode.episodeInfo.pubDate,
          duration: episode.episodeInfo.duration,
          guid: episode.episodeInfo.guid
        )
        EnhancedAudioManager.shared.playNext(playbackEpisode)
      },
      onDownload: {
        DownloadManager.shared.downloadEpisode(
          episode: episode.episodeInfo,
          podcastTitle: episode.podcastTitle,
          language: episode.language
        )
      },
      onCancelDownload: {
        DownloadManager.shared.cancelDownload(
          episodeTitle: episode.episodeInfo.title,
          podcastTitle: episode.podcastTitle
        )
      },
      onDeleteDownload: {
        DownloadManager.shared.deleteDownload(
          episodeTitle: episode.episodeInfo.title,
          podcastTitle: episode.podcastTitle
        )
      },
      onRetryDownload: {
        DownloadManager.shared.downloadEpisode(
          episode: episode.episodeInfo,
          podcastTitle: episode.podcastTitle,
          language: episode.language
        )
      }
    )
  }

  // MARK: - Up Next Section

  @ViewBuilder
  private var upNextSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Up Next")
            .font(.title2)
            .fontWeight(.bold)
          if viewModel.continueListeningCount > 0 {
            Text("\(viewModel.continueListeningCount) in progress")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        if !viewModel.upNextEpisodes.isEmpty {
          NavigationLink(value: UpNextListRoute(episodes: viewModel.upNextEpisodes)) {
            Text("See All")
              .font(.subheadline)
              .foregroundStyle(.blue)
          }
        }
      }
      .padding(.horizontal)

      if viewModel.upNextEpisodes.isEmpty {
        VStack(spacing: 8) {
          Image(systemName: "play.circle")
            .font(.system(size: 40))
            .foregroundStyle(.gray)
          Text("No unplayed episodes")
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Text("Subscribe to podcasts to see new episodes here")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
      } else {
        ScrollView(.horizontal) {
          HStack(spacing: 12) {
            ForEach(viewModel.scoredUpNextEpisodes.prefix(10)) { scored in
              NavigationLink(
                value: EpisodeDetailRoute(
                  episode: scored.episode.episodeInfo,
                  podcastTitle: scored.episode.podcastTitle,
                  fallbackImageURL: scored.episode.imageURL,
                  podcastLanguage: scored.episode.language
                )
              ) {
                UpNextCard(
                  episode: scored.episode,
                  onPlay: { viewModel.playEpisode(scored.episode) },
                  reason: scored.reason
                )
              }
              .buttonStyle(.plain)
              .contextMenu {
                upNextContextMenu(for: scored.episode)
              }
            }
          }
          .padding(.horizontal)
        }
        .scrollIndicators(.never)
        .animation(.default, value: viewModel.scoredUpNextIDs)
      }
    }
  }

  // MARK: - For You Section

  @available(iOS 26.0, macOS 26.0, *)
  @ViewBuilder
  private var forYouSection: some View {
    if viewModel.showForYouRecommendations && (!viewModel.recommendedEpisodes.isEmpty || viewModel.isLoadingRecommendations) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Image(systemName: "star.leadinghalf.filled")
            .foregroundStyle(.purple)
          Text("For You")
            .font(.title2)
            .fontWeight(.bold)

          Spacer()

          if viewModel.isLoadingRecommendations {
            ProgressView()
              .scaleEffect(0.8)
          } else {
            Button {
              viewModel.refreshRecommendations()
            } label: {
              Image(systemName: "arrow.clockwise")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
          }
        }
        .padding(.horizontal)

        if viewModel.isLoadingRecommendations && viewModel.recommendedEpisodes.isEmpty {
          HStack(spacing: 8) {
            ProgressView()
              .scaleEffect(0.7)
            Text("Finding episodes for you...")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 24)
        } else {
          ScrollView(.horizontal) {
            HStack(spacing: 12) {
              ForEach(Array(viewModel.recommendedEpisodes.enumerated()), id: \.element.id) { index, episode in
                NavigationLink(
                  value: EpisodeDetailRoute(
                    episode: episode.episodeInfo,
                    podcastTitle: episode.podcastTitle,
                    fallbackImageURL: episode.imageURL,
                    podcastLanguage: episode.language
                  )
                ) {
                  ForYouCard(
                    episode: episode
                  )
                }
                .buttonStyle(.plain)
                .contextMenu {
                  upNextContextMenu(for: episode)
                }
              }
            }
            .padding(.horizontal)
          }
          .scrollIndicators(.never)
        }
      }
    }
  }

  // MARK: - Trending Episodes Section

  @ViewBuilder
  private var trendingEpisodesSection: some View {
    if viewModel.showTrendingEpisodes && (!viewModel.trendingEpisodes.isEmpty || viewModel.isLoadingTrendingEpisodes) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Top Episodes")
            .font(.title2)
            .fontWeight(.bold)

          Spacer()

          if viewModel.isLoadingTrendingEpisodes {
            ProgressView()
              .scaleEffect(0.8)
          }

          if !viewModel.trendingEpisodes.isEmpty {
            NavigationLink(value: TrendingEpisodesDestination()) {
              HStack(spacing: 2) {
                Text("See All")
                  .font(.subheadline)
                Image(systemName: "chevron.right")
                  .font(.caption)
              }
              .foregroundStyle(.blue)
            }
          }
        }
        .padding(.horizontal)

        if viewModel.trendingEpisodes.isEmpty && viewModel.isLoadingTrendingEpisodes {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
          .frame(height: 120)
        } else {
          TrendingEpisodesPagedView(
            episodes: Array(viewModel.trendingEpisodes.prefix(12))
          )
        }
      }
    }
  }

  // MARK: - Popular Shows Section

  @ViewBuilder
  private var popularShowsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Popular Shows")
          .font(.title2)
          .fontWeight(.bold)

        Spacer()

        if viewModel.isLoadingTopPodcasts {
          ProgressView()
            .scaleEffect(0.8)
        }

        if !viewModel.topPodcasts.isEmpty {
          NavigationLink(value: PopularShowsDestination()) {
            Text("See All")
              .font(.subheadline)
              .foregroundStyle(.blue)
          }
        }
      }
      .padding(.horizontal)

      if viewModel.topPodcasts.isEmpty && !viewModel.isLoadingTopPodcasts {
        VStack(spacing: 8) {
          Image(systemName: "chart.line.uptrend.xyaxis")
            .font(.system(size: 40))
            .foregroundStyle(.gray)
          Text("Unable to load popular shows")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(viewModel.topPodcasts.prefix(25).enumerated()), id: \.element.id) { index, podcast in
            TopPodcastRow(
              podcast: podcast,
              rank: index + 1,
              isSubscribed: viewModel.isAlreadySubscribed(podcast),
              onSubscribe: { viewModel.subscribeToPodcast(podcast) }
            )
          }
        }
        .padding(.horizontal)
      }
    }
  }
}

#Preview {
  HomeView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
