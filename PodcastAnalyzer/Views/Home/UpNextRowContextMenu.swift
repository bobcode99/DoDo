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
    UpNextContextMenu(
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
      },
      onRemoveFromUpNext: { viewModel.dismissFromUpNext(episode) }
    )
  }
}
