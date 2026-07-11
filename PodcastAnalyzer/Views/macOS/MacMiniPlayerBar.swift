//
//  MacMiniPlayerBar.swift
//  PodcastAnalyzer
//
//  macOS floating mini player bar — Apple Podcasts style with glass background
//

#if os(macOS)
import SwiftUI

struct MacMiniPlayerBar: View {
  @Binding var showExpandedPlayer: Bool
  private var audioManager: EnhancedAudioManager { .shared }
  // Lightweight view model shared with PlayerControlsView for transport state.
  // Wraps EnhancedAudioManager.shared, so a second instance here doesn't
  // create a competing source of truth.
  @State private var playerViewModel = ExpandedPlayerViewModel()
  @State private var isHoveringProgress = false
  @State private var isDraggingProgress = false

  var body: some View {
    let content = VStack(spacing: 0) {
      // Interactive progress bar. The currentTime read lives inside this child
      // view, so periodic time-observer ticks (~4×/sec during playback)
      // re-render only the bar instead of the whole player (artwork, controls,
      // speed menu, glass background).
      MacMiniPlayerProgressBar(
        isHoveringProgress: $isHoveringProgress,
        isDraggingProgress: $isDraggingProgress
      )
      .frame(height: isHoveringProgress || isDraggingProgress ? 6 : 3)
      .animation(.easeInOut(duration: 0.15), value: isHoveringProgress)
      .onHover { hovering in
        isHoveringProgress = hovering
      }

      // Player controls
      HStack(spacing: 16) {
        // Left: Artwork and episode info (clickable to expand)
        Button(action: { showExpandedPlayer = true }) {
          HStack(spacing: 12) {
            if let episode = audioManager.currentEpisode {
              CachedArtworkImage(urlString: episode.imageURL, size: 48, cornerRadius: 6)

              VStack(alignment: .leading, spacing: 2) {
                Text(episode.title)
                  .font(.subheadline)
                  .fontWeight(.medium)
                  .lineLimit(1)
                  .foregroundStyle(.primary)

                Text(episode.podcastTitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              .frame(maxWidth: 320, alignment: .leading)
            }
          }
        }
        .buttonStyle(.plain)
        .help("Show full player")

        Spacer()

        // Center: Playback controls — shared with iOS/Mac expanded player
        PlayerControlsView(viewModel: playerViewModel, style: .compact)

        Spacer()

        // Right: Time, speed, and expand
        HStack(spacing: 12) {
          MacMiniPlayerTimeLabel()

          // Playback speed button
          Menu {
            ForEach(Formatters.playbackSpeeds, id: \.self) { speed in
              Button(action: { audioManager.setPlaybackRate(Float(speed)) }) {
                HStack {
                  Text(Formatters.formatSpeed(Float(speed)))
                  if abs(audioManager.playbackRate - Float(speed)) < 0.01 {
                    Image(systemName: "checkmark")
                  }
                }
              }
            }
          } label: {
            Text(Formatters.formatSpeed(audioManager.playbackRate))
              .font(.system(size: 11, weight: .medium))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(.ultraThinMaterial, in: .rect(cornerRadius: 4))
          }
          .menuStyle(.borderlessButton)
          .frame(width: 44)
          .help("Playback speed")

          // Expand button
          Button(action: { showExpandedPlayer = true }) {
            Image(systemName: "chevron.up.2")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .help("Expand player")
        }
        .frame(width: 220, alignment: .trailing)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
    }
    Group {
      if #available(macOS 26, *) {
        content
          .glassEffect(.regular, in: .rect(cornerRadius: 14))
      } else {
        content
          .clipShape(.rect(cornerRadius: 14))
          .background(.ultraThinMaterial, in: .rect(cornerRadius: 14))
      }
    }
    // Now floats directly over page content (Library lists, Episode Detail, etc.)
    // instead of sitting in a reserved safe-area strip, so it needs its own
    // elevation to read as a floating card rather than blending into the page.
    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
  }

}

// MARK: - Isolated progress bar

/// Reads `currentTime`/`duration` only inside this view so the high-frequency
/// time-observer ticks re-render just the bar, not the whole MacMiniPlayerBar.
private struct MacMiniPlayerProgressBar: View {
  @Binding var isHoveringProgress: Bool
  @Binding var isDraggingProgress: Bool
  private var audioManager: EnhancedAudioManager { .shared }

  private var progressPercentage: Double {
    guard audioManager.duration > 0 else { return 0 }
    return audioManager.currentTime / audioManager.duration
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(Color.gray.opacity(0.2))

        Rectangle()
          .fill(Color.accentColor)
          .frame(width: geometry.size.width * progressPercentage)
      }
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            isDraggingProgress = true
            let progress = max(0, min(1, value.location.x / geometry.size.width))
            let newTime = progress * audioManager.duration
            audioManager.seek(to: newTime)
          }
          .onEnded { _ in
            isDraggingProgress = false
          }
      )
    }
  }
}

// MARK: - Isolated time label

/// Isolates the per-tick "elapsed / total" text so it doesn't invalidate the
/// surrounding controls on every time-observer update.
private struct MacMiniPlayerTimeLabel: View {
  private var audioManager: EnhancedAudioManager { .shared }

  var body: some View {
    Text("\(Formatters.formatPlaybackTime(audioManager.currentTime)) / \(Formatters.formatPlaybackTime(audioManager.duration))")
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .monospacedDigit()
      .frame(width: 90, alignment: .trailing)
  }
}

#Preview {
  MacMiniPlayerBar(showExpandedPlayer: .constant(false))
    .frame(width: 800)
}

#endif
