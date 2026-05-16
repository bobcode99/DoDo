//
//  MacLibraryViews.swift
//  PodcastAnalyzer
//
//  macOS Library sub-views — Podcasts, Saved, Downloaded, Latest
//

#if os(macOS)
import SwiftData
import SwiftUI

// MARK: - Library Podcasts Grid

struct MacLibraryPodcastsView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext

  @Query(
    filter: #Predicate<PodcastInfoModel> { $0.isSubscribed },
    sort: \.lastUpdated,
    order: .reverse
  ) private var subscribedPodcasts: [PodcastInfoModel]

  private let columns = [
    GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16)
  ]

  var body: some View {
    ScrollView {
      if viewModel.podcastsSortedByRecentUpdate.isEmpty {
        ContentUnavailableView(
          "No Subscriptions",
          systemImage: "square.stack.3d.up",
          description: Text("Search and subscribe to podcasts to build your library")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        LazyVGrid(columns: columns, spacing: 20) {
          ForEach(viewModel.podcastsSortedByRecentUpdate) { podcast in
            NavigationLink(value: PodcastBrowseRoute(podcastModel: podcast)) {
              MacPodcastGridCell(podcast: podcast)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(24)
      }
    }
    .navigationTitle("Your Podcasts")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: {
          Task { await viewModel.refreshAllPodcasts() }
        }) {
          Image(systemName: "arrow.clockwise")
        }
        .disabled(viewModel.isLoading)
      }
    }
    .onAppear {
      viewModel.setModelContext(modelContext)
      viewModel.setPodcasts(subscribedPodcasts)
    }
    .onDisappear {
      viewModel.cleanup()
    }
    .onChange(of: subscribedPodcasts) { _, newPodcasts in
      viewModel.setPodcasts(newPodcasts)
    }
  }
}

// MARK: - Podcast Grid Cell

struct MacPodcastGridCell: View {
  let podcast: PodcastInfoModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CachedArtworkImage(urlString: podcast.podcastInfo.imageURL, size: 150, cornerRadius: 10)

      Text(podcast.podcastInfo.title)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2)
    }
    .frame(width: 150)
  }
}

// MARK: - Library Saved

struct MacLibrarySavedView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]

  private var audioManager: EnhancedAudioManager { .shared }

  var body: some View {
    Group {
      if viewModel.savedEpisodes.isEmpty {
        ContentUnavailableView(
          "No Saved Episodes",
          systemImage: "star",
          description: Text("Star episodes to save them here for later")
        )
      } else {
        List(viewModel.savedEpisodes) { episode in
          MacLibraryEpisodeListRow(
            episode: episode,
            podcastModel: viewModel.podcastInfoModelList.first {
              $0.podcastInfo.title == episode.podcastTitle
            },
            onToggleStar: {
              LibraryEpisodeActions.toggleStar(
                episode,
                episodeModels: &episodeModels,
                context: modelContext
              )
              Task { await viewModel.refreshSavedEpisodes() }
            },
            onTogglePlayed: {
              LibraryEpisodeActions.togglePlayed(
                episode,
                episodeModels: &episodeModels,
                context: modelContext
              )
            },
            onDeleteDownload: {
              LibraryEpisodeActions.deleteDownload(
                episode,
                episodeModels: episodeModels,
                context: modelContext
              )
            }
          )
        }
        .listStyle(.plain)
      }
    }
    .navigationTitle("Saved")
    .onAppear {
      viewModel.setModelContext(modelContext)
      episodeModels = LibraryEpisodeActions.batchFetchEpisodeModels(from: modelContext)
      // `setModelContext` no-ops on subsequent visits (`isAlreadyLoaded` short
      // circuits it). Without an explicit refresh here, a star toggled in
      // EpisodeDetailView — including on episodes from unsubscribed podcasts —
      // wouldn't show up until the next app launch.
      Task { await viewModel.refreshSavedEpisodes() }
    }
    .onDisappear {
      viewModel.cleanup()
    }
  }
}

// MARK: - Library Downloaded

struct MacLibraryDownloadedView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]

  private var audioManager: EnhancedAudioManager { .shared }

  var body: some View {
    Group {
      if viewModel.downloadedEpisodes.isEmpty {
        ContentUnavailableView(
          "No Downloads",
          systemImage: "arrow.down.circle",
          description: Text("Downloaded episodes will appear here for offline listening")
        )
      } else {
        List(viewModel.downloadedEpisodes) { episode in
          MacLibraryEpisodeListRow(
            episode: episode,
            podcastModel: viewModel.podcastInfoModelList.first {
              $0.podcastInfo.title == episode.podcastTitle
            },
            onToggleStar: {
              LibraryEpisodeActions.toggleStar(
                episode,
                episodeModels: &episodeModels,
                context: modelContext
              )
            },
            onTogglePlayed: {
              LibraryEpisodeActions.togglePlayed(
                episode,
                episodeModels: &episodeModels,
                context: modelContext
              )
            },
            onDeleteDownload: {
              LibraryEpisodeActions.deleteDownload(
                episode,
                episodeModels: episodeModels,
                context: modelContext
              )
            }
          )
        }
        .listStyle(.plain)
      }
    }
    .navigationTitle("Downloaded")
    .onAppear {
      viewModel.setModelContext(modelContext)
      episodeModels = LibraryEpisodeActions.batchFetchEpisodeModels(from: modelContext)
      // Same staleness fix as Saved — pick up newly-completed downloads
      // triggered from EpisodeDetailView / DownloadManager elsewhere.
      Task { await viewModel.refreshDownloadedEpisodes() }
    }
    .onDisappear {
      viewModel.cleanup()
    }
  }
}

// MARK: - Library Latest

struct MacLibraryLatestView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]

  private var audioManager: EnhancedAudioManager { .shared }

  var body: some View {
    Group {
      if viewModel.latestEpisodes.isEmpty {
        ContentUnavailableView(
          "No Episodes",
          systemImage: "clock",
          description: Text("Subscribe to podcasts to see latest episodes")
        )
      } else {
        List(viewModel.latestEpisodes) { episode in
          MacLibraryEpisodeListRow(
            episode: episode,
            podcastModel: viewModel.podcastInfoModelList.first {
              $0.podcastInfo.title == episode.podcastTitle
            },
            onToggleStar: {
              LibraryEpisodeActions.toggleStar(
                episode,
                episodeModels: &episodeModels,
                context: modelContext,
                createIfMissing: true
              )
              viewModel.setModelContext(modelContext)
            },
            onTogglePlayed: {
              LibraryEpisodeActions.togglePlayed(
                episode,
                episodeModels: &episodeModels,
                context: modelContext,
                createIfMissing: true
              )
              viewModel.setModelContext(modelContext)
            },
            onDeleteDownload: {
              LibraryEpisodeActions.deleteDownload(
                episode,
                episodeModels: episodeModels,
                context: modelContext
              )
              viewModel.setModelContext(modelContext)
            }
          )
        }
        .listStyle(.plain)
      }
    }
    .navigationTitle("Latest Episodes")
    .onAppear {
      viewModel.setModelContext(modelContext)
      episodeModels = LibraryEpisodeActions.batchFetchEpisodeModels(from: modelContext)
    }
    .onDisappear {
      viewModel.cleanup()
    }
  }
}

// MARK: - Library Episode List Row (with cached status observer)

/// Wraps MacLibraryEpisodeRow + NavigationLink + contextMenu.
/// Uses direct status reads so the list does not allocate one observer per row.
private struct MacLibraryEpisodeListRow: View {
  let episode: LibraryEpisode
  let podcastModel: PodcastInfoModel?
  let onToggleStar: () -> Void
  let onTogglePlayed: () -> Void
  let onDeleteDownload: () -> Void

  private var audioManager: EnhancedAudioManager { .shared }
  private var statusChecker: EpisodeStatusChecker {
    EpisodeStatusChecker(episode: episode)
  }

  var body: some View {
    NavigationLink(value: EpisodeDetailRoute(
      episode: episode.episodeInfo,
      podcastTitle: episode.podcastTitle,
      fallbackImageURL: episode.imageURL,
      podcastLanguage: episode.language
    )) {
      MacLibraryEpisodeRow(
        episode: episode.episodeInfo,
        podcastTitle: episode.podcastTitle,
        podcastImageURL: episode.imageURL ?? "",
        podcastLanguage: episode.language
      )
    }
    .contextMenu {
      LibraryEpisodeContextMenu(
        episode: episode,
        isStarred: episode.isStarred,
        isCompleted: episode.isCompleted,
        downloadState: statusChecker.downloadState,
        podcastModel: podcastModel,
        onPlay: {
          let playbackURL = statusChecker.playbackURL
          guard !playbackURL.isEmpty else { return }
          let playbackEpisode = PlaybackEpisode(
            id: statusChecker.episodeKey,
            title: episode.episodeInfo.title,
            podcastTitle: episode.podcastTitle,
            audioURL: playbackURL,
            imageURL: episode.imageURL ?? "",
            episodeDescription: episode.episodeInfo.podcastEpisodeDescription,
            pubDate: episode.episodeInfo.pubDate,
            duration: episode.episodeInfo.duration,
            guid: episode.episodeInfo.guid
          )
          audioManager.play(
            episode: playbackEpisode,
            audioURL: playbackURL,
            startTime: episode.lastPlaybackPosition,
            imageURL: episode.imageURL ?? "",
            useDefaultSpeed: true
          )
        },
        onPlayNext: {
          let playbackURL = statusChecker.playbackURL
          guard !playbackURL.isEmpty else { return }
          let playbackEpisode = PlaybackEpisode(
            id: statusChecker.episodeKey,
            title: episode.episodeInfo.title,
            podcastTitle: episode.podcastTitle,
            audioURL: playbackURL,
            imageURL: episode.imageURL ?? "",
            episodeDescription: episode.episodeInfo.podcastEpisodeDescription,
            pubDate: episode.episodeInfo.pubDate,
            duration: episode.episodeInfo.duration,
            guid: episode.episodeInfo.guid
          )
          audioManager.playNext(playbackEpisode)
        },
        onToggleStar: onToggleStar,
        onTogglePlayed: onTogglePlayed,
        onDownload: { LibraryEpisodeActions.downloadEpisode(episode) },
        onCancelDownload: {
          DownloadManager.shared.cancelDownload(
            episodeTitle: episode.episodeInfo.title,
            podcastTitle: episode.podcastTitle
          )
        },
        onDeleteDownload: onDeleteDownload,
        onShare: {
          if let audioURL = episode.episodeInfo.audioURL,
             let url = URL(string: audioURL) {
            PlatformShareSheet.share(url: url)
          }
        }
      )
    }
  }
}

// MARK: - Library Podcast Row

struct MacLibraryPodcastRow: View {
  let podcastModel: PodcastInfoModel

  var body: some View {
    HStack(spacing: 12) {
      CachedArtworkImage(urlString: podcastModel.podcastInfo.imageURL, size: 56, cornerRadius: 8)

      VStack(alignment: .leading, spacing: 2) {
        Text(podcastModel.podcastInfo.title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)

        Text("Show · \(podcastModel.podcastInfo.episodes.count) episodes")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Image(systemName: "checkmark")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.primary)
    }
    .padding(.vertical, 4)
  }
}

// MARK: - Library Episode Row

struct MacLibraryEpisodeRow: View {
  let episode: PodcastEpisodeInfo
  let podcastTitle: String
  let podcastImageURL: String
  let podcastLanguage: String

  private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }

  var body: some View {
    HStack(spacing: 12) {
      CachedArtworkImage(urlString: episode.imageURL ?? podcastImageURL, size: 56, cornerRadius: 8)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
          if let date = episode.pubDate {
            Text(date.formatted(date: .abbreviated, time: .omitted))
          }
          if let duration = episode.formattedDuration {
            Text("·")
            Text(duration)
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)

        Text(episode.title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)
      }

      Spacer()

      if episode.audioURL != nil {
        Button(action: {
          playEpisode()
        }) {
          Image(systemName: "play.fill")
            .font(.title3)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Color.accentColor)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 4)
  }

  private func playEpisode() {
    guard let audioURL = episode.audioURL else { return }

    let playbackEpisode = PlaybackEpisode(
      id: "\(podcastTitle)\u{1F}\(episode.title)",
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: audioURL,
      imageURL: episode.imageURL ?? podcastImageURL,
      episodeDescription: episode.podcastEpisodeDescription,
      pubDate: episode.pubDate,
      duration: episode.duration,
      guid: episode.guid
    )

    audioManager.play(
      episode: playbackEpisode,
      audioURL: audioURL,
      startTime: 0,
      imageURL: episode.imageURL ?? podcastImageURL,
      useDefaultSpeed: true
    )
  }
}

#endif
