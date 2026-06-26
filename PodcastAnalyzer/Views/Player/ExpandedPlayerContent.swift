import SwiftUI

/// Body of the expanded player: a single centered column, capped so it stays
/// readable on wide (iPad) presentations. Split out of ExpandedPlayerView so
/// the host keeps navigation, queue, and lifecycle.
struct ExpandedPlayerContent: View {
    let viewModel: ExpandedPlayerViewModel
    let onNavigateToEpisodeDetail: () -> Void
    let onNavigateToPodcast: () -> Void
    let onOpenQueue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    PlayerArtworkView(imageURL: viewModel.imageURL, isPlaying: viewModel.isPlaying)
                        .padding(.top, 16)
                    episodeInfo
                        .padding(.top, 24)
                }

                Spacer(minLength: 20)

                VStack(spacing: 32) {
                    scrubber
                    controls
                    volumeRow
                }

                Spacer(minLength: 32)

                bottomActions
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center)
        }
    }

    // MARK: - Shared chrome

    private var episodeInfo: some View {
        PlayerEpisodeInfoView(
            viewModel: viewModel,
            onNavigateToEpisodeDetail: onNavigateToEpisodeDetail,
            onNavigateToPodcast: onNavigateToPodcast
        )
    }

    private var scrubber: some View {
        PlayerScrubberBar(viewModel: viewModel)
    }

    private var controls: some View {
        PlayerControlsView(viewModel: viewModel)
    }

    @ViewBuilder
    private var volumeRow: some View {
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

    private var bottomActions: some View {
        PlayerBottomActionsView(
            queueCount: viewModel.queue.count,
            onNavigateToEpisodeDetail: onNavigateToEpisodeDetail,
            onOpenQueue: onOpenQueue
        )
    }
}

/// Isolates the per-tick `currentTime` read so playback updates invalidate
/// only the scrubber, not the rest of the player.
private struct PlayerScrubberBar: View {
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
