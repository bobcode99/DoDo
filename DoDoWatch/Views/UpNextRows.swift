//
//  UpNextRows.swift
//  DoDoWatch
//
//  Up Next, as rows on the home list: the Play Next queue (QueueItemModel,
//  synced through CloudKit), then the rest of the phone's Up Next as it last
//  pushed it — the suggestions Home shows. The queue alone was usually empty.
//

import SwiftData
import SwiftUI

struct UpNextRows: View {
  @Query(sort: \QueueItemModel.position) private var queue: [QueueItemModel]
  @State private var session = WatchSessionManager.shared

  /// Rows on a wrist past this are never scrolled to.
  private static let limit = 10

  private var episodes: [WatchPlayableEpisode] {
    Array(
      Self.merged(queue: queue.map(WatchPlayableEpisode.init(queueItem:)), phoneUpNext: session.upNext)
        .prefix(Self.limit))
  }

  /// Queue first, in queue order, then the phone's list without repeats. The
  /// phone's list already starts with its queue, but CloudKit may be ahead of
  /// or behind the last push, so both are merged rather than either trusted.
  static func merged(queue: [WatchPlayableEpisode], phoneUpNext: [PlaybackEpisode]) -> [WatchPlayableEpisode] {
    var seen = Set(queue.map(\.id))
    let rest = phoneUpNext.compactMap { episode -> WatchPlayableEpisode? in
      guard seen.insert(episode.id).inserted else { return nil }
      return WatchPlayableEpisode(playbackEpisode: episode)
    }
    return queue + rest
  }

  var body: some View {
    if episodes.isEmpty {
      Text("Open DoDo on your iPhone to load Up Next.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    } else {
      ForEach(episodes) { episode in
        NavigationLink {
          PlayerScreen()
            .task { await start(episode) }
        } label: {
          EpisodeRow(title: episode.title, subtitle: episode.podcastTitle, imageURL: episode.imageURL)
        }
      }
    }
  }

  private func start(_ episode: WatchPlayableEpisode) async {
    let resumeAt = WatchProgressStore.shared.position(for: episode.progressKey)
    await WatchAudioPlayer.shared.play(episode, resumingAt: resumeAt)
  }
}
