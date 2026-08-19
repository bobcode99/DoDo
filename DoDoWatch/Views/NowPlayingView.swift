//
//  NowPlayingView.swift
//  DoDoWatch
//
//  Transport controls for whichever source the user picked.
//
//  The two sources are read directly rather than through a protocol: an
//  existential would hide the @Observable type SwiftUI needs to see in order to
//  track it. Pocket Casts can use a ~50-member protocol here
//  (UI/Play Source/PlaySourceViewModel.swift) because their views are driven by
//  Combine publishers instead.
//

import SwiftUI

struct NowPlayingView: View {
  @State private var sourceManager = SourceManager.shared
  @State private var player = WatchAudioPlayer.shared
  @State private var session = WatchSessionManager.shared

  var body: some View {
    Group {
      switch sourceManager.selected {
      case .watch: watchSource
      case .phone: phoneSource
      }
    }
    .navigationTitle("Now Playing")
    // A half-listened episode is otherwise lost if the user just drops their
    // wrist — the periodic observer only updates memory.
    .onDisappear { player.checkpoint() }
  }

  @ViewBuilder
  private var watchSource: some View {
    if let message = player.failureMessage {
      ContentUnavailableView(
        "Can't Play",
        systemImage: "exclamationmark.triangle",
        description: Text(message)
      )
    } else if let episode = player.episode {
      PlayerControls(
        title: episode.title,
        currentTime: player.currentTime,
        duration: player.duration,
        progress: player.progress,
        isPlaying: player.isPlaying,
        onToggle: { player.togglePlayPause() },
        onSkipBack: { player.skipBackward() },
        onSkipForward: { player.skipForward() }
      )
    } else {
      empty("Pick an episode from Shows.")
    }
  }

  @ViewBuilder
  private var phoneSource: some View {
    if let snapshot = session.nowPlaying {
      PlayerControls(
        title: snapshot.episodeTitle,
        currentTime: snapshot.currentTime,
        duration: snapshot.duration,
        progress: snapshot.progress,
        isPlaying: snapshot.isPlaying,
        onToggle: { session.send(.togglePlayPause) },
        onSkipBack: { session.send(.skipBackward) },
        onSkipForward: { session.send(.skipForward) }
      )
    } else {
      empty("Start something on your iPhone.")
    }
  }

  private func empty(_ message: String) -> some View {
    ContentUnavailableView(
      "Nothing Playing",
      systemImage: "headphones",
      description: Text(message)
    )
  }
}

/// The controls themselves, given plain values — so both sources render
/// identically and neither one owns the layout.
private struct PlayerControls: View {
  let title: String
  let currentTime: TimeInterval
  let duration: TimeInterval
  let progress: Double
  let isPlaying: Bool
  let onToggle: () -> Void
  let onSkipBack: () -> Void
  let onSkipForward: () -> Void

  var body: some View {
    VStack(spacing: 6) {
      Text(title)
        .font(.caption)
        .lineLimit(2)
        .multilineTextAlignment(.center)

      ProgressView(value: progress)
        .tint(.accentColor)

      HStack {
        Text(Self.format(currentTime))
        Spacer()
        Text(duration > 0 ? Self.format(duration) : "--:--")
      }
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .monospacedDigit()

      HStack(spacing: 14) {
        Button(action: onSkipBack) { Image(systemName: "gobackward.15") }
        Button(action: onToggle) {
          Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            .font(.title3)
        }
        Button(action: onSkipForward) { Image(systemName: "goforward.30") }
      }
      .buttonStyle(.plain)
      .font(.title3)
    }
    .padding(.horizontal, 4)
  }

  static func format(_ time: TimeInterval) -> String {
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
