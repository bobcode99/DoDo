//
//  EpisodePlayButtonWithProgress.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/4.
//

import SwiftData
import Foundation
import SwiftUI

/// A more detailed play button that shows progress information inline
struct EpisodePlayButtonWithProgress: View {
  let isPlaying: Bool
  let isPlayingThisEpisode: Bool
  let isCompleted: Bool
  let playbackProgress: Double
  let duration: TimeInterval?
  let lastPlaybackPosition: TimeInterval
  let formattedDuration: String?
  let isDisabled: Bool
  let action: () -> Void

  init(
    isPlaying: Bool,
    isPlayingThisEpisode: Bool,
    isCompleted: Bool = false,
    playbackProgress: Double = 0,
    duration: TimeInterval? = nil,
    lastPlaybackPosition: TimeInterval = 0,
    formattedDuration: String? = nil,
    isDisabled: Bool = false,
    action: @escaping () -> Void
  ) {
    self.isPlaying = isPlaying
    self.isPlayingThisEpisode = isPlayingThisEpisode
    self.isCompleted = isCompleted
    self.playbackProgress = playbackProgress
    self.duration = duration
    self.lastPlaybackPosition = lastPlaybackPosition
    self.formattedDuration = formattedDuration
    self.isDisabled = isDisabled
    self.action = action
  }

  private var durationText: String? {
      // Determine which value to format: remaining time or total duration
      let isInProgress = playbackProgress > 0 && playbackProgress < 1
      guard let totalSeconds = duration, totalSeconds > 0 else { return nil }
      
      let secondsToFormat = isInProgress ? (totalSeconds - lastPlaybackPosition) : totalSeconds
      let timeString = formatTimeUnits(Int(secondsToFormat))
      
      return isInProgress ? "\(timeString) left" : timeString
  }

  private func formatTimeUnits(_ totalSeconds: Int) -> String {
      let seconds = max(0, totalSeconds)
      let h = seconds / 3600
      let m = (seconds % 3600) / 60
      let s = seconds % 60

      if h > 0 {
          // "1h 5m"
          return "\(h)h \(m)m"
      } else if m > 0 {
          // "50m"
          return "\(m)m"
      } else {
          // "0:44"
          return String(format: "0:%02d", s)
      }
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        // Play/Pause/Replay icon
        if isPlayingThisEpisode && isPlaying {
          Image(systemName: "pause.fill")
            .font(.system(size: 9))
        } else if isCompleted {
          Image(systemName: "arrow.counterclockwise")
            .font(.system(size: 9, weight: .bold))
        } else {
          Image(systemName: "play.fill")
            .font(.system(size: 9))
        }

        // Progress bar (only when partially played)
        if playbackProgress > 0 && playbackProgress < 1 {
          ProgressView(value: playbackProgress)
            .progressViewStyle(.linear)
            .tint(.white)
            .frame(width: 24)
        }

        // Duration text
        if let duration = durationText {
          Text(duration)
            .font(.system(size: 10))
            .fontWeight(.medium)
        }
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(Color.blue)
      .clipShape(Capsule())
    }
    .buttonStyle(.borderless)
    .disabled(isDisabled)
  }
}

// MARK: - Reactive Play Button for LibraryEpisode (Deprecated)

/// A reactive version that observes EnhancedAudioManager for live playback updates
@available(*, deprecated, renamed: "LivePlaybackButton", message: "Use LivePlaybackButton instead for live playback state")
struct ReactiveEpisodePlayButton: View {
  let episode: LibraryEpisode
  let action: () -> Void

  // Observe audioManager to trigger re-renders on playback state changes
  private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }

  // State for triggering periodic refreshes during playback
  @State private var refreshTrigger = false

  init(episode: LibraryEpisode, action: @escaping () -> Void) {
    self.episode = episode
    self.action = action
  }

  private var isPlayingThisEpisode: Bool {
    audioManager.currentEpisode?.title == episode.episodeInfo.title
      && audioManager.currentEpisode?.podcastTitle == episode.podcastTitle
  }

  private var livePlaybackProgress: Double {
    // Use live data if this episode is currently playing
    if isPlayingThisEpisode && audioManager.duration > 0 {
      return audioManager.currentTime / audioManager.duration
    }
    // Fall back to saved progress
    return episode.progress
  }

  private var livePlaybackPosition: TimeInterval {
    if isPlayingThisEpisode {
      return audioManager.currentTime
    }
    return episode.lastPlaybackPosition
  }

  var body: some View {
    EpisodePlayButtonWithProgress(
      isPlaying: audioManager.isPlaying,
      isPlayingThisEpisode: isPlayingThisEpisode,
      isCompleted: episode.isCompleted,
      playbackProgress: livePlaybackProgress,
      duration: episode.episodeInfo.duration.map { TimeInterval($0) },
      lastPlaybackPosition: livePlaybackPosition,
      formattedDuration: episode.episodeInfo.formattedDuration,
      isDisabled: episode.episodeInfo.audioURL == nil,
      action: action
    )
    .task(id: isPlayingThisEpisode) {
      // Task-based timer for periodic updates during playback
      guard isPlayingThisEpisode else { return }
      while !Task.isCancelled && isPlayingThisEpisode {
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { break }
        refreshTrigger.toggle()
      }
    }
  }
}