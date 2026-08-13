//
//  MacLibraryEpisodeListView.swift
//  PodcastAnalyzer
//
//  Shared episode list body for Saved / Downloaded / Latest — they differ
//  only in data source, empty-state copy, and `createIfMissing` behavior.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacLibraryEpisodeListView: View {
  let episodes: [LibraryEpisode]
  let podcastInfoModelList: [PodcastInfoModel]
  let emptyTitle: String
  let emptySystemImage: String
  let emptyDescription: String
  let createIfMissing: Bool
  let modelContext: ModelContext
  @Binding var episodeModels: [String: EpisodeDownloadModel]
  /// Extra hook run after a star toggle (e.g. Saved re-filters its list by star state).
  var onToggleStar: (() -> Void)?
  /// Extra hook run after played-toggle / delete (view-model-specific rebind, if needed).
  var onEpisodeMutated: (() -> Void)?

  var body: some View {
    Group {
      if episodes.isEmpty {
        ContentUnavailableView(
          emptyTitle,
          systemImage: emptySystemImage,
          description: Text(emptyDescription)
        )
      } else {
        List(episodes) { episode in
          MacLibraryEpisodeListRow(
            episode: episode,
            podcastModel: podcastInfoModelList.first {
              $0.title == episode.podcastTitle
            },
            onToggleStar: {
              LibraryEpisodeActions.toggleStar(
                episode,
                episodeModels: &episodeModels,
                context: modelContext,
                createIfMissing: createIfMissing
              )
              onToggleStar?()
            },
            onTogglePlayed: {
              LibraryEpisodeActions.togglePlayed(
                episode,
                episodeModels: &episodeModels,
                context: modelContext,
                createIfMissing: createIfMissing
              )
              onEpisodeMutated?()
            },
            onDeleteDownload: {
              LibraryEpisodeActions.deleteDownload(
                episode,
                episodeModels: episodeModels,
                context: modelContext
              )
              onEpisodeMutated?()
            }
          )
        }
        .listStyle(.plain)
      }
    }
  }
}

// MARK: - Library Episode List Row (with cached status observer)

/// Wraps MacLibraryEpisodeRow + NavigationLink + contextMenu.
/// Uses direct status reads so the list does not allocate one observer per row.
struct MacLibraryEpisodeListRow: View {
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
          // Completed episodes always restart from 0 — see EpisodeRowView.playAction().
          audioManager.play(
            episode: playbackEpisode,
            audioURL: playbackURL,
            startTime: episode.isCompleted ? 0 : episode.lastPlaybackPosition,
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
#endif
