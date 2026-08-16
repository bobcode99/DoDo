//
//  DownloadsView.swift
//  DoDoWatch
//
//  Episodes held on the watch. These play with no network at all, which is the
//  point of downloading to a watch in the first place.
//

import SwiftData
import SwiftUI

struct DownloadsView: View {
  @Query(sort: \WatchDownloadModel.downloadedDate, order: .reverse)
  private var downloads: [WatchDownloadModel]

  var body: some View {
    List {
      if downloads.isEmpty {
        ContentUnavailableView(
          "No Downloads",
          systemImage: "arrow.down.circle",
          description: Text("Download an episode to play it offline.")
        )
      } else {
        ForEach(downloads) { download in
          NavigationLink {
            NowPlayingView()
              .task { await start(download) }
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(download.episodeTitle)
                .font(.body)
                .lineLimit(2)
              Text(download.podcastTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .swipeActions {
            Button(role: .destructive) {
              WatchDownloadManager.shared.delete(id: download.id)
            } label: {
              Label("Delete", systemImage: "trash")
            }
          }
        }
      }
    }
    .navigationTitle("Downloads")
  }

  private func start(_ download: WatchDownloadModel) async {
    let episode = WatchPlayableEpisode(
      id: download.id,
      title: download.episodeTitle,
      podcastTitle: download.podcastTitle,
      audioURL: download.audioURL,
      localPath: download.localPath
    )
    let resumeAt = WatchProgressStore.shared.position(for: episode.progressKey)
    await WatchAudioPlayer.shared.play(episode, resumingAt: resumeAt)
  }
}
