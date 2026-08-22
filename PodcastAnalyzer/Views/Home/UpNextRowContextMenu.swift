//
//  UpNextRowContextMenu.swift
//  PodcastAnalyzer
//
//  Long-press context menu for a single Up Next / For You card.
//  Constructs the `EpisodeStatusChecker` in its own body so the
//  `DownloadManager.downloadStates` observation registers against this leaf
//  view instead of the parent ScrollView — otherwise every download progress
//  tick would invalidate the entire Home body.
//

import SwiftUI

struct UpNextRowContextMenu: View {
  let episode: LibraryEpisode
  let viewModel: HomeViewModel

  var body: some View {
    let checker = EpisodeStatusChecker(episode: episode)
    let isQueued = EnhancedAudioManager.shared.queue.contains { $0.id == episode.id }
    UpNextContextMenu(
      episode: episode,
      isStarred: episode.isStarred,
      isCompleted: episode.isCompleted,
      downloadState: checker.downloadState,
      podcastModel: viewModel.findPodcastModel(for: episode.podcastTitle),
      onToggleStar: { viewModel.toggleStar(for: episode) },
      onTogglePlayed: { viewModel.togglePlayed(for: episode) },
      onPlayNext: {
        guard let playbackEpisode = PlaybackEpisode(episode) else { return }
        EnhancedAudioManager.shared.playNext(playbackEpisode)
      },
      onAddToQueue: {
        guard let playbackEpisode = PlaybackEpisode(episode) else { return }
        EnhancedAudioManager.shared.addToQueue(playbackEpisode)
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
      },
      onRemoveFromQueue: isQueued
        ? {
          guard let playbackEpisode = PlaybackEpisode(episode) else { return }
          EnhancedAudioManager.shared.removeFromQueue(playbackEpisode)
        }
        : nil,
      onDismissSuggestion: { viewModel.dismissFromUpNext(episode) }
    )
  }
}
