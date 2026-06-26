import SwiftUI

// Shared player chrome. Both the iPhone (`ExpandedPlayerContent`) and iPad
// (`ExpandedPlayerPadContent`) layouts compose these exact pieces, so the two
// presentations share one source of truth — only the arrangement differs.

/// Isolates the per-tick `currentTime` read so playback updates invalidate
/// only the scrubber, not the surrounding layout.
struct PlayerScrubberBar: View {
    let viewModel: ExpandedPlayerViewModel

    var body: some View {
        SmoothScrubber(
            currentTime: viewModel.currentTime,
            duration: viewModel.duration,
            isDurationLoading: viewModel.isDurationLoading,
            onSeek: viewModel.seekToProgress
        )
        .padding(.horizontal, 32)
    }
}

/// System volume slider flanked by speaker glyphs (iOS only).
struct PlayerVolumeRow: View {
    var body: some View {
        #if os(iOS)
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            SystemVolumeSlider()
                .frame(height: 32)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 32)
        #endif
    }
}
