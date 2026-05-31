//
//  MacHomeContentView.swift
//  PodcastAnalyzer
//
//  macOS Home tab content — Up Next, For You, Trending Episodes, Popular Shows
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacHomeContentView: View {
  @State private var viewModel = HomeViewModel()
  @State private var syncManager = BackgroundSyncManager.shared
  @Environment(\.modelContext) private var modelContext
  @State private var showRegionPicker = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        upNextSection

        if #available(macOS 26.0, *) {
          forYouSection
        }

        trendingEpisodesSection

        popularShowsSection
      }
      .padding(.vertical, 24)
    }
    .navigationTitle("Home")
    .navigationDestination(for: TrendingEpisodesDestination.self) { _ in
      TrendingEpisodesListView(episodes: viewModel.trendingEpisodes)
    }
    .navigationDestination(for: PopularShowsDestination.self) { _ in
      PopularShowsListView(podcasts: viewModel.topPodcasts, viewModel: viewModel)
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
        }
        .help("Change region")
      }
    }
    .sheet(isPresented: $showRegionPicker) {
      RegionPickerSheet(
        selectedRegion: $viewModel.selectedRegion,
        isPresented: $showRegionPicker
      )
      .frame(minWidth: 360, minHeight: 480)
    }
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
    .onDisappear {
      viewModel.cleanup()
    }
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
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 24)

      if viewModel.upNextEpisodes.isEmpty {
        emptyState(
          systemImage: "play.circle",
          title: "No unplayed episodes",
          message: "Subscribe to podcasts to see new episodes here"
        )
      } else {
        ScrollView(.horizontal) {
          HStack(spacing: 14) {
            ForEach(viewModel.scoredUpNextEpisodes.prefix(12)) { scored in
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
          .padding(.horizontal, 24)
        }
        .scrollIndicators(.never)
        .animation(.default, value: viewModel.scoredUpNextIDs)
      }
    }
  }

  // MARK: - For You Section

  @available(macOS 26.0, *)
  @ViewBuilder
  private var forYouSection: some View {
    if viewModel.showForYouRecommendations
      && (!viewModel.recommendedEpisodes.isEmpty || viewModel.isLoadingRecommendations) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Image(systemName: "star.leadinghalf.filled")
            .foregroundStyle(.purple)
          Text("For You")
            .font(.title2)
            .fontWeight(.bold)

          Spacer()

          if viewModel.isLoadingRecommendations {
            ProgressView().scaleEffect(0.8)
          } else {
            Button {
              viewModel.refreshRecommendations()
            } label: {
              Image(systemName: "arrow.clockwise")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Refresh recommendations")
          }
        }
        .padding(.horizontal, 24)

        if viewModel.isLoadingRecommendations && viewModel.recommendedEpisodes.isEmpty {
          HStack(spacing: 8) {
            ProgressView().scaleEffect(0.7)
            Text("Finding episodes for you...")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 24)
        } else {
          ScrollView(.horizontal) {
            HStack(spacing: 14) {
              ForEach(viewModel.recommendedEpisodes) { episode in
                NavigationLink(
                  value: EpisodeDetailRoute(
                    episode: episode.episodeInfo,
                    podcastTitle: episode.podcastTitle,
                    fallbackImageURL: episode.imageURL,
                    podcastLanguage: episode.language
                  )
                ) {
                  ForYouCard(episode: episode)
                }
                .buttonStyle(.plain)
                .contextMenu {
                  upNextContextMenu(for: episode)
                }
              }
            }
            .padding(.horizontal, 24)
          }
          .scrollIndicators(.never)
        }
      }
    }
  }

  // MARK: - Trending Episodes Section

  @ViewBuilder
  private var trendingEpisodesSection: some View {
    if viewModel.showTrendingEpisodes
      && (!viewModel.trendingEpisodes.isEmpty || viewModel.isLoadingTrendingEpisodes) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Top Episodes")
            .font(.title2)
            .fontWeight(.bold)

          Spacer()

          if viewModel.isLoadingTrendingEpisodes {
            ProgressView().scaleEffect(0.8)
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
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 24)

        if viewModel.trendingEpisodes.isEmpty && viewModel.isLoadingTrendingEpisodes {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
          .frame(height: 120)
        } else {
          MacTrendingEpisodesGrid(
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
          ProgressView().scaleEffect(0.8)
        }

        if !viewModel.topPodcasts.isEmpty {
          NavigationLink(value: PopularShowsDestination()) {
            Text("See All")
              .font(.subheadline)
              .foregroundStyle(.blue)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 24)

      if viewModel.topPodcasts.isEmpty && !viewModel.isLoadingTopPodcasts {
        emptyState(
          systemImage: "chart.line.uptrend.xyaxis",
          title: "Unable to load popular shows",
          message: "Check your internet connection"
        )
      } else {
        // `TopPodcastRow` is designed for full-width list rows (trailing
        // chevron, single-line title, full-width Divider). Use a LazyVStack
        // so each row spans the section width — matches iOS HomeView.
        LazyVStack(spacing: 0) {
          ForEach(Array(viewModel.topPodcasts.prefix(30).enumerated()), id: \.element.id) { index, podcast in
            TopPodcastRow(
              podcast: podcast,
              rank: index + 1,
              isSubscribed: viewModel.isAlreadySubscribed(podcast),
              onSubscribe: { viewModel.subscribeToPodcast(podcast) }
            )
          }
        }
        .padding(.horizontal, 24)
      }
    }
  }

  // MARK: - Helpers

  @ViewBuilder
  private func emptyState(
    systemImage: String,
    title: LocalizedStringKey,
    message: LocalizedStringKey
  ) -> some View {
    VStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.system(size: 40))
        .foregroundStyle(.gray)
      Text(title)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 32)
  }

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
}

#endif
