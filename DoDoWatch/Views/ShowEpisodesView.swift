//
//  ShowEpisodesView.swift
//  DoDoWatch
//
//  Episodes for one show. The episode list is not synced — only the
//  subscription pointer is — so the watch fetches the feed itself with the
//  same PodcastRssService the phone uses.
//

import SwiftUI

struct ShowEpisodesView: View {
  let rssUrl: String
  let title: String

  @State private var downloads = WatchDownloadManager.shared
  @State private var episodes: [PodcastEpisodeInfo] = []
  @State private var loadFailed = false

  /// Enough to scroll on a watch without holding a whole back-catalogue in
  /// memory. The feed is fetched in full either way; this only caps the list.
  private static let episodeLimit = 50

  var body: some View {
    List {
      if loadFailed {
        ContentUnavailableView {
          Label("Couldn't Load", systemImage: "wifi.exclamationmark")
        } description: {
          Text("Check your connection and try again.")
        } actions: {
          // Without this the only retry is backing out of the screen and
          // re-entering it, since `.task(id:)` will not re-run for the same id.
          Button("Retry") { Task { await load() } }
        }
      } else if episodes.isEmpty {
        ProgressView()
          .frame(maxWidth: .infinity)
      } else {
        ForEach(episodes) { episode in
          if let playable = WatchPlayableEpisode(episode: episode, podcastTitle: title) {
            NavigationLink {
              NowPlayingView()
                .task { await start(playable) }
            } label: {
              episodeRow(episode)
            }
            .swipeActions {
              if downloads.isDownloaded(playable.progressKey) {
                Button(role: .destructive) {
                  downloads.delete(id: playable.progressKey)
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              } else {
                Button {
                  downloads.download(playable)
                } label: {
                  Label("Download", systemImage: "arrow.down.circle")
                }
              }
            }
          } else {
            // No enclosure in the feed — show it, but it cannot be played.
            episodeRow(episode)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle(title)
    .task(id: rssUrl) { await load() }
  }

  private func episodeRow(_ episode: PodcastEpisodeInfo) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(episode.title)
        .font(.body)
        .lineLimit(3)
      if let pubDate = episode.pubDate {
        Text(pubDate, format: .dateTime.month().day())
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// Picks up wherever this Apple ID left off — the position may have been
  /// written by the iPhone rather than by this watch.
  private func start(_ episode: WatchPlayableEpisode) async {
    let resumeAt = WatchProgressStore.shared.position(for: episode.progressKey)
    await WatchAudioPlayer.shared.play(episode, resumingAt: resumeAt)
  }

  private func load() async {
    loadFailed = false
    do {
      let info = try await PodcastRssService().fetchPodcast(from: rssUrl)
      episodes = Array(info.episodes.prefix(Self.episodeLimit))
      loadFailed = false
    } catch {
      loadFailed = true
    }
  }
}
