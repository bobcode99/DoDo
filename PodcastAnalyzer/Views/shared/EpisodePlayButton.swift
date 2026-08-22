//
//  EpisodePlayButton.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/4.
//

import SwiftData
import Foundation
import SwiftUI

// MARK: - Live Episode Play Button (Deprecated)

/// Wrapper that provides live playback time updates when episode is currently playing
/// Falls back to SwiftData values when episode is not playing
@available(*, deprecated, renamed: "LivePlaybackButton", message: "Use LivePlaybackButton instead for live playback state")
struct LiveEpisodePlayButton: View {
  let episodeTitle: String
  let podcastTitle: String
  let duration: Int?
  let lastPlaybackPosition: TimeInterval
  let isCompleted: Bool
  let formattedDuration: String?
  let isDisabled: Bool
  let onPlay: () -> Void

  private var audioManager: EnhancedAudioManager { .shared }

  /// Unique key for this episode (matches episodeKey format)
  private var episodeKey: String {
    "\(podcastTitle)\u{1F}\(episodeTitle)"
  }

  /// Whether this episode is currently loaded in the audio manager
  private var isCurrentEpisode: Bool {
    audioManager.currentEpisode?.id == episodeKey
  }

  /// Current playback position - live if playing, otherwise from SwiftData
  private var currentPosition: TimeInterval {
    if isCurrentEpisode {
      return audioManager.currentTime
    }
    return lastPlaybackPosition
  }

  /// Duration - live if this episode is playing, otherwise from SwiftData
  private var currentDuration: TimeInterval? {
    if isCurrentEpisode, audioManager.duration > 0 {
      return audioManager.duration
    }
    return duration.map { TimeInterval($0) }
  }

  /// Progress - live if playing, otherwise calculated from SwiftData
  private var currentProgress: Double {
    if isCurrentEpisode, audioManager.duration > 0 {
      return audioManager.currentTime / audioManager.duration
    }
    guard let d = duration, d > 0 else { return 0 }
    return min(lastPlaybackPosition / Double(d), 1.0)
  }

  /// Whether playback is complete (always uses SwiftData value since audio manager doesn't track this)
  private var playbackCompleted: Bool {
    isCompleted
  }

  var body: some View {
    EpisodePlayButton(
      isPlaying: audioManager.isPlaying,
      isPlayingThisEpisode: isCurrentEpisode,
      isCompleted: playbackCompleted,
      playbackProgress: currentProgress,
      duration: currentDuration,
      lastPlaybackPosition: currentPosition,
      formattedDuration: formattedDuration,
      isDisabled: isDisabled,
      style: .compact,
      action: onPlay
    )
  }
}

// MARK: - Episode Play Button (Deprecated)

/// Reusable play button with progress indicator
/// Shows play/pause/replay icon, progress bar when partially played, and duration text
@available(*, deprecated, renamed: "LivePlaybackButton", message: "Use LivePlaybackButton instead for live playback state")
struct EpisodePlayButton: View {
  /// Whether the audio manager is currently playing
  let isPlaying: Bool
  /// Whether this specific episode is the current one in the audio manager
  let isPlayingThisEpisode: Bool
  /// Whether the episode has been completed
  let isCompleted: Bool
  /// Playback progress (0.0 to 1.0)
  let playbackProgress: Double
  /// Total duration in seconds (optional)
  let duration: TimeInterval?
  /// Last playback position in seconds
  let lastPlaybackPosition: TimeInterval
  /// Formatted duration string (e.g., "45m") - used when no progress
  let formattedDuration: String?
  /// Whether the button should be disabled (e.g., no audio URL)
  let isDisabled: Bool
  /// Style variant for different contexts
  let style: PlayButtonStyle
  /// Action to perform when tapped
  let action: () -> Void

  enum PlayButtonStyle {
    case compact      // For list rows (smaller, capsule shape)
    case standard     // For detail views (larger, bordered prominent)
    case iconOnly     // Icon + duration only, capsule with semantic color
  }

  init(
    isPlaying: Bool,
    isPlayingThisEpisode: Bool,
    isCompleted: Bool = false,
    playbackProgress: Double = 0,
    duration: TimeInterval? = nil,
    lastPlaybackPosition: TimeInterval = 0,
    formattedDuration: String? = nil,
    isDisabled: Bool = false,
    style: PlayButtonStyle = .compact,
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
    self.style = style
    self.action = action
  }

  /// Convenience initializer from EpisodeDownloadModel data
  init(
    audioManager: EnhancedAudioManager,
    episodeTitle: String,
    podcastTitle: String,
    episodeModel: EpisodeDownloadModel?,
    formattedDuration: String?,
    isDisabled: Bool = false,
    style: PlayButtonStyle = .compact,
    action: @escaping () -> Void
  ) {
    let isPlayingThis = audioManager.currentEpisode?.title == episodeTitle
      && audioManager.currentEpisode?.podcastTitle == podcastTitle

    self.isPlaying = audioManager.isPlaying
    self.isPlayingThisEpisode = isPlayingThis
    self.isCompleted = episodeModel?.isCompleted ?? false
    self.playbackProgress = episodeModel?.progress ?? 0
    self.duration = episodeModel?.duration
    self.lastPlaybackPosition = episodeModel?.lastPlaybackPosition ?? 0
    self.formattedDuration = formattedDuration
    self.isDisabled = isDisabled
    self.style = style
    self.action = action
  }

  private var durationText: String? {
      let isInProgress = showsPlaybackProgress

      if let totalSeconds = duration, totalSeconds > 0 {
          let secondsToFormat = isInProgress ? (totalSeconds - lastPlaybackPosition) : totalSeconds
          let timeString = formatTimeUnits(Int(secondsToFormat))
          return isInProgress ? "\(timeString)\(remainingTimeSuffix)" : timeString
      }

      return formattedDuration
  }

  private var showsPlaybackProgress: Bool {
      playbackProgress > 0 && playbackProgress < 1 && lastPlaybackPosition >= 1
  }

  private var localeIdentifier: String {
      Locale.current.identifier.lowercased()
  }

  private var languageCode: String {
      Locale.current.language.languageCode?.identifier ?? "en"
  }

  private var usesChineseUnits: Bool {
      languageCode.hasPrefix("zh")
  }

  private var usesSimplifiedChinese: Bool {
      localeIdentifier.contains("hans")
  }

  private var remainingTimeSuffix: String {
      if usesChineseUnits {
          return usesSimplifiedChinese ? "剩余" : "剩餘"
      }
      return " left"
  }

  private func formatTimeUnits(_ totalSeconds: Int) -> String {
      let seconds = max(0, totalSeconds)
      let h = seconds / 3600
      let m = (seconds % 3600) / 60
      let s = seconds % 60
      let hourUnit = usesChineseUnits ? "時" : "h"
      let minuteUnit = usesChineseUnits ? "分" : "m"

      if h > 0 {
          return "\(h)\(hourUnit) \(m)\(minuteUnit)"
      } else if m > 0 {
          return "\(m)\(minuteUnit)"
      } else {
          return String(format: "0:%02d", s)
      }
  }

  var body: some View {
    switch style {
    case .compact:
      compactButton
    case .standard:
      standardButton
    case .iconOnly:
      iconOnlyButton
    }
  }

  // MARK: - Compact Style (for list rows)

  private var compactButton: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        // Icon
        playIcon(size: 9)

        // Progress bar (only show when partially played)
        if showsPlaybackProgress {
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

  // MARK: - Standard Style (for detail views)

  private var standardButton: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        playIcon(size: 12)
        Text(buttonLabel)
          .font(.caption)
          .fontWeight(.medium)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
    }
    .buttonStyle(.accentProminent)
    .disabled(isDisabled)
  }

  // MARK: - Icon Only Style (capsule with icon, progress bar, and duration)

  private var iconOnlyButton: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        playIcon(size: 14)

        // Progress bar (only show when partially played)
        if showsPlaybackProgress {
          ProgressView(value: playbackProgress)
            .progressViewStyle(.linear)
            .tint(.white)
            .frame(width: 32)
        }

        if let duration = durationText {
          Text(duration)
            .font(.caption)
            .fontWeight(.medium)
        }
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(Color.blue)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
  }

  // MARK: - Helpers

  @ViewBuilder
  private func playIcon(size: CGFloat) -> some View {
    if isPlayingThisEpisode && isPlaying {
      Image(systemName: "pause.fill")
        .font(.system(size: size))
    } else if isCompleted {
      Image(systemName: "arrow.counterclockwise")
        .font(.system(size: size, weight: .bold))
    } else {
      Image(systemName: "play.fill")
        .font(.system(size: size))
    }
  }

  private var buttonLabel: String {
    if isPlayingThisEpisode && isPlaying {
      return "Pause"
    } else if isCompleted {
      return "Replay"
    } else {
      return "Play"
    }
  }
}
