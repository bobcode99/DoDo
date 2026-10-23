//
//  MacPlaybackCommands.swift
//  PodcastAnalyzer
//
//  Controls menu in the macOS menu bar.
//

#if os(macOS)
import SwiftUI

/// Playback is app-global (one `EnhancedAudioManager`), so these commands talk
/// to the shared manager rather than a focused scene value.
struct MacPlaybackCommands: Commands {
  private var audioManager: EnhancedAudioManager { .shared }
  private var navigation: NotificationNavigationManager { .shared }

  var body: some Commands {
    CommandMenu("Controls") {
      let hasEpisode = audioManager.currentEpisode != nil

      Button(audioManager.isPlaying ? "Pause" : "Play", action: togglePlayPause)
        .keyboardShortcut(.space, modifiers: [])
        .disabled(!hasEpisode)

      Button("Skip Forward", action: skipForward)
        .keyboardShortcut(.rightArrow)
        .disabled(!hasEpisode)

      Button("Skip Back", action: skipBackward)
        .keyboardShortcut(.leftArrow)
        .disabled(!hasEpisode)

      Button("Play Next Episode", action: audioManager.playNextInQueue)
        .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        .disabled(audioManager.queue.isEmpty)

      Divider()

      // Routed through setPlaybackRate so the player and saved rate stay in step.
      Picker("Playback Speed", selection: Binding(
        get: { audioManager.playbackRate },
        set: { audioManager.setPlaybackRate($0) }
      )) {
        ForEach(Formatters.playbackSpeeds, id: \.self) { speed in
          Text(Formatters.formatSpeed(speed)).tag(speed)
        }
      }

      Divider()

      Button("Show Full Player", action: showFullPlayer)
        .disabled(!hasEpisode)

      Button("Go to Current Episode", action: goToCurrentEpisode)
        .keyboardShortcut("l")
        .disabled(!hasEpisode)
    }
  }

  private func togglePlayPause() {
    if audioManager.isPlaying {
      audioManager.pause()
    } else {
      audioManager.resume()
    }
  }

  private func skipForward() {
    audioManager.skipForward()
  }

  private func skipBackward() {
    audioManager.skipBackward()
  }

  // Both need a window to act in, and the app keeps running after its last
  // window closes.
  private func showFullPlayer() {
    MacBackgroundMode.presentMainWindow()
    navigation.requestExpandPlayer()
  }

  private func goToCurrentEpisode() {
    MacBackgroundMode.presentMainWindow()
    navigation.navigateToNowPlaying()
  }
}
#endif
