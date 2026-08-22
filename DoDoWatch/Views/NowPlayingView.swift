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
        subtitle: episode.podcastTitle,
        currentTime: player.currentTime,
        duration: player.duration,
        progress: player.progress,
        isPlaying: player.isPlaying,
        onToggle: { player.togglePlayPause() },
        onSkipBack: { player.skipBackward() },
        onSkipForward: { player.skipForward() },
        onScrub: { player.seek(to: $0) }
      )
    } else {
      empty("Pick an episode from Shows.")
    }
  }

  @ViewBuilder
  private var phoneSource: some View {
    if let snapshot = session.nowPlaying, !snapshot.episodeTitle.isEmpty {
      PlayerControls(
        title: snapshot.episodeTitle,
        subtitle: snapshot.podcastTitle,
        currentTime: snapshot.currentTime,
        duration: snapshot.duration,
        progress: snapshot.progress,
        isPlaying: snapshot.isPlaying,
        onToggle: { session.send(.togglePlayPause) },
        onSkipBack: { session.send(.skipBackward) },
        onSkipForward: { session.send(.skipForward) },
        // Scrubbing the phone from the wrist is a single seek command rather
        // than a stream of them — the phone owns the timeline.
        onScrub: { session.send(.seek(to: $0)) }
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
///
/// Sizing is the point of this layout. Apple's 44×44pt minimum target applies
/// on a 41mm screen too, and the previous version drew bare `.title3` glyphs
/// with `.buttonStyle(.plain)`, which makes the tappable area the glyph itself —
/// roughly 20pt, and unhittable while walking. Every control below claims a
/// real frame.
private struct PlayerControls: View {
  let title: String
  let subtitle: String
  let currentTime: TimeInterval
  let duration: TimeInterval
  let progress: Double
  let isPlaying: Bool
  let onToggle: () -> Void
  let onSkipBack: () -> Void
  let onSkipForward: () -> Void
  let onScrub: (TimeInterval) -> Void

  /// Crown position, in seconds. Held separately from `currentTime` so the
  /// crown does not fight the playback clock: it is seeded when scrubbing
  /// starts and only written back on release.
  @State private var scrubTarget: TimeInterval = 0
  @State private var isScrubbing = false

  private var canScrub: Bool { duration > 0 }
  private var shownTime: TimeInterval { isScrubbing ? scrubTarget : currentTime }
  private var shownProgress: Double {
    guard duration > 0 else { return progress }
    return min(max(shownTime / duration, 0), 1)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      timeline
      Spacer(minLength: 6)
      buttons
    }
    .padding(.horizontal, 2)
  }

  private var header: some View {
    VStack(spacing: 1) {
      Text(subtitle)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Text(title)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.85)
    }
    .frame(maxWidth: .infinity)
  }

  private var timeline: some View {
    VStack(spacing: 3) {
      ProgressView(value: shownProgress)
        .tint(isScrubbing ? .orange : WatchTheme.accent)

      HStack(spacing: 0) {
        Text(Self.format(shownTime))
        Spacer(minLength: 4)
        Text(duration > 0 ? "−" + Self.format(max(duration - shownTime, 0)) : "--:--")
      }
      .font(.system(size: 12, weight: .medium))
      .foregroundStyle(isScrubbing ? .orange : .secondary)
      .monospacedDigit()
    }
    .padding(.top, 7)
    // The crown is the one input a watch has that a phone does not, and
    // scrubbing a 90-minute episode with two skip buttons is the worst part of
    // every watch podcast app. Focus lives on the timeline so a crown turn
    // reads as "move through the episode".
    .focusable(canScrub)
    .digitalCrownRotation(
      detent: $scrubTarget,
      from: 0,
      through: max(duration, 1),
      by: max(duration / 120, 5),
      sensitivity: .medium,
      isContinuous: false,
      isHapticFeedbackEnabled: true
    ) { _ in
      // Turning began. Seed from the live clock so the first detent starts
      // where playback actually is, not from wherever the last scrub ended.
      if !isScrubbing {
        scrubTarget = currentTime
        isScrubbing = true
      }
    } onIdle: {
      guard isScrubbing else { return }
      isScrubbing = false
      onScrub(scrubTarget)
    }
  }

  private var buttons: some View {
    HStack(spacing: 6) {
      TransportButton(
        systemImage: "gobackward.15",
        accessibilityLabel: "Back 15 seconds",
        diameter: 44,
        glyphSize: 19,
        action: onSkipBack
      )

      TransportButton(
        systemImage: isPlaying ? "pause.fill" : "play.fill",
        accessibilityLabel: isPlaying ? "Pause" : "Play",
        diameter: 58,
        glyphSize: 25,
        isProminent: true,
        action: onToggle
      )

      TransportButton(
        systemImage: "goforward.30",
        accessibilityLabel: "Forward 30 seconds",
        diameter: 44,
        glyphSize: 19,
        action: onSkipForward
      )
    }
    .frame(maxWidth: .infinity)
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

/// A circular target with a real frame, so the hit area is the circle rather
/// than the glyph inside it.
private struct TransportButton: View {
  let systemImage: String
  let accessibilityLabel: LocalizedStringResource
  let diameter: CGFloat
  let glyphSize: CGFloat
  var isProminent: Bool = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: glyphSize, weight: .semibold))
        .foregroundStyle(isProminent ? AnyShapeStyle(.black) : AnyShapeStyle(.primary))
        .frame(width: diameter, height: diameter)
        .background(
          isProminent ? AnyShapeStyle(WatchTheme.accent) : AnyShapeStyle(.fill.tertiary),
          in: .circle
        )
        // Symbols with a number in them ("15", "30") shrink to nothing at these
        // sizes if the glyph is allowed to scale with the frame.
        .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(accessibilityLabel))
  }
}
