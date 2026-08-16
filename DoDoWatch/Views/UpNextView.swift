//
//  UpNextView.swift
//  DoDoWatch
//
//  The phone's Play Next queue. QueueItemModel moved into the CloudKit-synced
//  store for this screen, so there is nothing to fetch and no message to send —
//  the rows are simply here.
//

import SwiftData
import SwiftUI

struct UpNextView: View {
  @Query(sort: \QueueItemModel.position) private var queue: [QueueItemModel]

  var body: some View {
    List {
      if queue.isEmpty {
        ContentUnavailableView(
          "Nothing Queued",
          systemImage: "text.line.first.and.arrowtriangle.forward",
          description: Text("Add episodes to Play Next on your iPhone.")
        )
      } else {
        ForEach(queue) { item in
          NavigationLink {
            NowPlayingView()
              .task { await start(WatchPlayableEpisode(queueItem: item)) }
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(item.episodeTitle)
                .font(.body)
                .lineLimit(2)
              Text(item.podcastTitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        }
      }
    }
    .navigationTitle("Up Next")
  }

  private func start(_ episode: WatchPlayableEpisode) async {
    let resumeAt = WatchProgressStore.shared.position(for: episode.progressKey)
    await WatchAudioPlayer.shared.play(episode, resumingAt: resumeAt)
  }
}
