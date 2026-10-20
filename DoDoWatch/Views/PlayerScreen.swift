//
//  PlayerScreen.swift
//  DoDoWatch
//
//  The system Now Playing controls — the screen Apple's own audio apps use:
//  play/pause, skips, the crown for volume, the AirPlay button for output. It
//  shows this watch's playback, or the iPhone's when the watch isn't playing,
//  so there is no "play on" choice to make.
//

import SwiftUI
import WatchKit

struct PlayerScreen: View {
  @State private var player = WatchAudioPlayer.shared
  @State private var session = WatchSessionManager.shared
  @State private var showOptions = false

  /// Whether the screen is showing the watch's own playback rather than the iPhone's.
  private var watchIsPlaying: Bool {
    player.episode != nil && (player.isPlaying || session.nowPlaying?.isPlaying != true)
  }

  var body: some View {
    Group {
      // The system view has no error state; a dead URL would otherwise look
      // like a player that never starts.
      if let message = player.failureMessage {
        ContentUnavailableView(
          "Can't Play",
          systemImage: "exclamationmark.triangle",
          description: Text(message)
        )
      } else {
        NowPlayingView()
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("More", systemImage: "ellipsis") { showOptions = true }
      }
    }
    .sheet(isPresented: $showOptions) {
      PlayerOptionsView(showsWatchControls: watchIsPlaying)
    }
    // A half-listened episode is otherwise lost if the user just drops their wrist.
    .onDisappear { player.checkpoint() }
  }
}
