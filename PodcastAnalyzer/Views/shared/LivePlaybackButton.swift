//
//  LivePlaybackButton.swift
//  PodcastAnalyzer
//
//  Unified play button component that directly observes EnhancedAudioManager
//  for live playback state - no polling needed.
//

import SwiftUI

/// Unified play button that shows live playback state by directly observing the audio manager.
/// Falls back to SwiftData values when the episode is not currently playing.
@MainActor
struct LivePlaybackButton: View {
  @Environment(\.locale) private var locale
  /// Only the `.compact` style honours this — it is the one used in episode
  /// rows, where the default pill is under the 44pt tap target. Read from the
  /// environment (set once at the app root) rather than UserDefaults, so a
  /// long list does not pay one observer per row.
  @Environment(\.episodeRowPlayButtonSize) private var compactSize

  // MARK: - Episode Identity
  
  /// Episode title for matching with audio manager
  let episodeTitle: String
  /// Podcast title for matching with audio manager
  let podcastTitle: String
  
  // MARK: - Episode Metadata (fallback when not playing)
  
  /// Duration in seconds from episode metadata
  let duration: TimeInterval?
  /// Formatted duration string (e.g., "45m") - used when no progress
  let formattedDuration: String?
  /// Last saved playback position from SwiftData
  var lastPlaybackPosition: TimeInterval = 0
  /// Saved progress (0.0 to 1.0) from SwiftData
  var playbackProgress: Double = 0
  /// Whether the episode has been completed
  var isCompleted: Bool = false
  
  // MARK: - Actions
  
  /// Action to perform when play/pause button is tapped
  let onPlay: () -> Void
  
  // MARK: - Style
  
  /// Visual style variant
  var style: ButtonStyle = .compact
  
  /// Whether the button should be disabled (e.g., no audio URL)
  var isDisabled: Bool = false
  
  enum ButtonStyle {
    case compact      // For list rows (smaller, capsule shape)
    case standard     // For detail views (larger, bordered prominent)
    case iconOnly     // Icon + duration only, capsule with semantic color
  }
  
  // MARK: - Live State from AudioManager
  
  private var audioManager: EnhancedAudioManager { .shared }
  
  /// Unique key for this episode (matches episodeKey format)
  private var episodeKey: String {
    "\(podcastTitle)\u{1F}\(episodeTitle)"
  }
  
  /// Whether this episode is currently loaded in the audio manager
  private var isCurrentEpisode: Bool {
    audioManager.currentEpisode?.id == episodeKey
  }
  
  /// Whether this episode is currently playing
  private var isPlayingThisEpisode: Bool {
    isCurrentEpisode && audioManager.isPlaying
  }
  
  /// Live progress - from audio manager if playing, otherwise from SwiftData
  private var liveProgress: Double {
    if isCurrentEpisode, audioManager.duration > 0 {
      return audioManager.currentTime / audioManager.duration
    }
    return playbackProgress
  }

  /// Normalized progress used for UI display. Prefer deriving from actual position
  /// and duration so stale saved ratios do not show progress when position is 0:00.
  private var displayProgress: Double {
    if let totalSeconds = liveDuration, totalSeconds > 0 {
      let normalized = livePosition / totalSeconds
      return min(max(normalized, 0), 1)
    }
    return min(max(liveProgress, 0), 1)
  }
  
  /// Live position - from audio manager if playing, otherwise from SwiftData
  private var livePosition: TimeInterval {
    if isCurrentEpisode {
      return audioManager.currentTime
    }
    return lastPlaybackPosition
  }
  
  /// Live duration - from audio manager if playing, otherwise from metadata
  private var liveDuration: TimeInterval? {
    if isCurrentEpisode, audioManager.duration > 0 {
      return audioManager.duration
    }
    return duration
  }
  
  /// Computed duration text for display
  private var durationText: String? {
    let isInProgress = showsPlaybackProgress
    
    // If we have duration, use it for precise calculation
    if let totalSeconds = liveDuration, totalSeconds > 0 {
      let secondsToFormat = isInProgress ? (totalSeconds - livePosition) : totalSeconds
      let timeString = formatTimeUnits(Int(secondsToFormat))
      return timeString
    }
    
    // Fallback to formatted duration from episode metadata (for unplayed episodes)
    return formattedDuration
  }
  
  // MARK: - Body
  
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

  private var showsPlaybackProgress: Bool {
    // Show progress as soon as playback has meaningfully started instead of
    // waiting for 1% progress, which hides the bar for ~1 minute on long episodes.
    displayProgress > 0 && displayProgress < 1 && livePosition > 0
  }

  private var localeIdentifier: String {
    locale.identifier.lowercased()
  }

  private var languageCode: String {
    locale.language.languageCode?.identifier ?? "en"
  }

  private var usesChineseUnits: Bool {
    languageCode.hasPrefix("zh")
  }

  private var usesSimplifiedChinese: Bool {
    localeIdentifier.contains("hans")
  }
  
  // MARK: - Compact Style (for list rows)
  
  private var compactButton: some View {
    let s = compactSize.scale
    return Button(action: onPlay) {
      HStack(spacing: 4 * s) {
        // Icon
        playIcon(size: 9 * s)

        // Progress bar (only show when partially played)
        if showsPlaybackProgress {
          progressBar(width: 24 * s, height: 3 * s)
        }

        // Duration text
        if let duration = durationText {
          Text(duration)
            .font(.system(size: 10 * s))
            .fontWeight(.medium)
        }
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 8 * s)
      .padding(.vertical, 5 * s)
      .background(Color.blue)
      .clipShape(Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.borderless)
    .disabled(isDisabled)
  }
  
  // MARK: - Standard Style (for detail views)
  
  private var standardButton: some View {
    Button(action: onPlay) {
      HStack(spacing: 6) {
        playIcon(size: 12)
        Text(buttonLabel)
          .font(.caption)
          .fontWeight(.medium)

        // Progress bar + remaining/total time so the prominent button still
        // surfaces "how much is left", like the icon-only style does.
        if showsPlaybackProgress {
          progressBar(width: 28, height: 3)
        }
        if let duration = durationText {
          Text(duration)
            .font(.caption)
            .fontWeight(.medium)
            .contentTransition(.identity)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
    }
    .buttonStyle(.accentProminent)
    .disabled(isDisabled)
    .transaction { $0.animation = nil }
  }
  
  // MARK: - Icon Only Style (capsule with icon, progress bar, and duration)
  //
  // Tap responsiveness: every time `audioManager.currentTime` ticks, this
  // body re-evaluates, the progress bar's width and the duration text both
  // change, and any animation inherited from a parent (sheet transitions,
  // navigation, list reorder) snaps the tween onto those layout changes —
  // making the button feel laggy right after the tap. `.transaction` strips
  // the inherited animation locally so the icon flip + progress update land
  // on the next frame instead of crossfading.
  private var iconOnlyButton: some View {
    Button(action: onPlay) {
      HStack(spacing: 6) {
        playIcon(size: 14)
          .contentTransition(.identity)

        // Progress bar (only show when partially played)
        if showsPlaybackProgress {
          progressBar(width: 32, height: 3)
        }

        if let duration = durationText {
          Text(duration)
            .font(.caption)
            .fontWeight(.medium)
            .contentTransition(.identity)
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
    .transaction { $0.animation = nil }
  }
  
  // MARK: - Helpers
  
  @ViewBuilder
  private func playIcon(size: CGFloat) -> some View {
    if isPlayingThisEpisode {
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
    if isPlayingThisEpisode {
      return "Pause"
    } else if isCompleted {
      return "Replay"
    } else {
      return "Play"
    }
  }

  @ViewBuilder
  private func progressBar(width: CGFloat, height: CGFloat) -> some View {
    let clampedProgress = min(max(displayProgress, 0), 1)

    ZStack(alignment: .leading) {
      Capsule()
        .fill(.white.opacity(0.28))
        .frame(width: width, height: height)

      Capsule()
        .fill(.white)
        .frame(width: max(width * clampedProgress, height), height: height)
    }
    .accessibilityHidden(true)
  }
  
  /// Format seconds into human-readable time units
  private func formatTimeUnits(_ totalSeconds: Int) -> String {
    let seconds = max(0, totalSeconds)
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    let hourUnit = usesChineseUnits ? (usesSimplifiedChinese ? "时" : "時") : "h"
    let minuteUnit = "分"
    
    if h > 0 {
      return usesChineseUnits ? "\(h)\(hourUnit) \(m)\(minuteUnit)" : "\(h)h \(m)m"
    } else if m > 0 {
      return usesChineseUnits ? "\(m)\(minuteUnit)" : "\(m)m"
    } else {
      return String(format: "0:%02d", s)
    }
  }
}

// MARK: - Convenience Initializer for LibraryEpisode

extension LivePlaybackButton {
  /// Convenience initializer for LibraryEpisode (used in UpNext, Library views)
  init(
    episode: LibraryEpisode,
    isDisabled: Bool = false,
    style: ButtonStyle = .compact,
    action: @escaping () -> Void
  ) {
    self.episodeTitle = episode.episodeInfo.title
    self.podcastTitle = episode.podcastTitle
    // Prefer savedDuration (measured by AVPlayer) for accurate "X left" text;
    // fall back to RSS duration which may be inaccurate for some podcasts.
    let rssDuration = episode.episodeInfo.duration.map { TimeInterval($0) }
    self.duration = episode.savedDuration > 0 ? episode.savedDuration : rssDuration
    self.formattedDuration = episode.episodeInfo.formattedDuration
    self.lastPlaybackPosition = episode.lastPlaybackPosition
    self.playbackProgress = episode.progress
    self.isCompleted = episode.isCompleted
    self.isDisabled = isDisabled || episode.episodeInfo.audioURL == nil
    self.style = style
    self.onPlay = action
  }
}
