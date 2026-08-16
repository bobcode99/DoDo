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

  @State private var episodes: [PodcastEpisodeInfo] = []
  @State private var loadFailed = false

  /// Enough to scroll on a watch without holding a whole back-catalogue in
  /// memory. The feed is fetched in full either way; this only caps the list.
  private static let episodeLimit = 50

  var body: some View {
    List {
      if loadFailed {
        ContentUnavailableView(
          "Couldn't Load",
          systemImage: "wifi.exclamationmark",
          description: Text("Check your connection and try again.")
        )
      } else if episodes.isEmpty {
        ProgressView()
          .frame(maxWidth: .infinity)
      } else {
        ForEach(episodes) { episode in
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
      }
    }
    .navigationTitle(title)
    .task(id: rssUrl) { await load() }
  }

  private func load() async {
    do {
      let info = try await PodcastRssService().fetchPodcast(from: rssUrl)
      episodes = Array(info.episodes.prefix(Self.episodeLimit))
      loadFailed = false
    } catch {
      loadFailed = true
    }
  }
}
