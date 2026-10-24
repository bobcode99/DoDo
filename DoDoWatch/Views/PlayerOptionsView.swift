//
//  PlayerOptionsView.swift
//  DoDoWatch
//
//  Behind the player's "…": what plays next, where the sound goes, and speed.
//

import AVFAudio
import SwiftData
import SwiftUI

struct PlayerOptionsView: View {
  /// Output and speed belong to the watch's own player; while the iPhone is
  /// playing they would describe audio nobody is hearing.
  let showsWatchControls: Bool

  @Environment(\.dismiss) private var dismiss
  @Query(sort: \QueueItemModel.position) private var queue: [QueueItemModel]
  @State private var player = WatchAudioPlayer.shared
  @State private var session = WatchSessionManager.shared

  private static let playingNextLimit = 5

  private var playingNext: [WatchPlayableEpisode] {
    let current = player.episode?.progressKey
    return Array(
      UpNextRows.merged(queue: queue.map(WatchPlayableEpisode.init(queueItem:)), phoneUpNext: session.upNext)
        .filter { $0.progressKey != current }
        .prefix(Self.playingNextLimit))
  }

  /// ponytail: read-only — watchOS has no public route picker, so switching
  /// stays on the system player's AirPlay button.
  private var output: AVAudioSessionPortDescription? {
    AVAudioSession.sharedInstance().currentRoute.outputs.first
  }

  var body: some View {
    List {
      Section("Playing Next") {
        if playingNext.isEmpty {
          Text("Nothing queued.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(playingNext) { episode in
            Button {
              Task { await start(episode) }
              dismiss()
            } label: {
              EpisodeRow(title: episode.title, subtitle: episode.podcastTitle, imageURL: episode.imageURL)
            }
          }
        }
      }

      if showsWatchControls {
        Section {
          Label(
            output?.portName ?? String(localized: "Apple Watch"),
            systemImage: output?.portType == .builtInSpeaker ? "applewatch" : "airplay.audio"
          )
          if session.isReachable {
            Button("iPhone", systemImage: "iphone", action: playOnPhone)
          }
        } header: {
          Text("AirPlay")
        } footer: {
          Text("For headphones or speakers, use the AirPlay button on the player.")
        }

        Section("Playback Speed") {
          ForEach(WatchAudioPlayer.supportedRates, id: \.self) { rate in
            Button {
              player.setRate(rate)
              dismiss()
            } label: {
              HStack {
                Text("\(rate, format: .number)×")
                Spacer()
                if player.rate == rate {
                  Image(systemName: "checkmark")
                    .accessibilityHidden(true)
                }
              }
            }
            .accessibilityAddTraits(player.rate == rate ? .isSelected : [])
          }
        }
      }
    }
  }

  private func playOnPhone() {
    guard let episode = player.episode else { return }
    session.send(
      .play(
        PlaybackEpisode(
          id: episode.progressKey, title: episode.title, podcastTitle: episode.podcastTitle,
          audioURL: episode.audioURL, imageURL: episode.imageURL),
        at: player.currentTime))
    player.stop()
    dismiss()
  }

  private func start(_ episode: WatchPlayableEpisode) async {
    let resumeAt = WatchProgressStore.shared.position(for: episode.progressKey)
    await WatchAudioPlayer.shared.play(episode, resumingAt: resumeAt)
  }
}
