//
//  NowPlayingView.swift
//  DoDoWatch
//
//  Transport controls for whatever the watch is playing.
//

import SwiftUI

struct NowPlayingView: View {
  @State private var player = WatchAudioPlayer.shared

  var body: some View {
    Group {
      if let episode = player.episode {
        playing(episode)
      } else {
        ContentUnavailableView(
          "Nothing Playing",
          systemImage: "headphones",
          description: Text("Pick an episode from Shows.")
        )
      }
    }
    .navigationTitle("Now Playing")
    // A half-listened episode is otherwise lost if the user just drops their
    // wrist — the periodic observer only updates memory.
    .onDisappear { player.checkpoint() }
  }

  private func playing(_ episode: WatchPlayableEpisode) -> some View {
    VStack(spacing: 6) {
      Text(episode.title)
        .font(.caption)
        .lineLimit(2)
        .multilineTextAlignment(.center)

      ProgressView(value: player.progress)
        .tint(.accentColor)

      HStack {
        Text(Self.format(player.currentTime))
        Spacer()
        Text(player.duration > 0 ? Self.format(player.duration) : "--:--")
      }
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .monospacedDigit()

      HStack(spacing: 14) {
        Button {
          player.skipBackward()
        } label: {
          Image(systemName: "gobackward.15")
        }

        Button {
          player.togglePlayPause()
        } label: {
          Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            .font(.title3)
        }

        Button {
          player.skipForward()
        } label: {
          Image(systemName: "goforward.30")
        }
      }
      .buttonStyle(.plain)
      .font(.title3)
    }
    .padding(.horizontal, 4)
  }

  private static func format(_ time: TimeInterval) -> String {
    guard time.isFinite, time >= 0 else { return "--:--" }
    let total = Int(time)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    return hours > 0
      ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
      : String(format: "%d:%02d", minutes, seconds)
  }
}
