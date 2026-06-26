import SwiftUI

/// Adaptive body of the expanded player: two columns when the area is wider
/// than it is tall (iPad/iPhone landscape), a single centered column otherwise.
/// Every size scales from the container, so it fits any iPhone or iPad size and
/// follows rotation. Pure layout — navigation and queue presentation stay with
/// the host `ExpandedPlayerView`.
struct ExpandedPlayerContent: View {
    let viewModel: ExpandedPlayerViewModel
    let onNavigateToEpisodeDetail: () -> Void
    let onNavigateToPodcast: () -> Void
    let onOpenQueue: () -> Void

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                layout(for: geo.size)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
            }
        }
    }

    // MARK: - Adaptive layout

    @ViewBuilder
    private func layout(for size: CGSize) -> some View {
        if size.width > size.height * 1.1 {
            horizontalPlayer(in: size)
        } else {
            verticalPlayer(in: size)
        }
    }

    private func verticalPlayer(in size: CGSize) -> some View {
        let art = min(size.width * 0.74, size.height * 0.42)
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                artwork(side: art)
                    .padding(.top, 16)
                episodeInfo
                    .padding(.top, 24)
            }

            Spacer(minLength: 24)

            VStack(spacing: 32) {
                scrubber
                controls
                volumeRow
            }

            Spacer(minLength: 32)

            bottomActions
                .padding(.bottom, 40)
        }
        .frame(maxWidth: min(size.width * 0.92, 560))
        .frame(maxWidth: .infinity)
    }

    private func horizontalPlayer(in size: CGSize) -> some View {
        let art = min(size.width * 0.42, size.height * 0.82)
        return HStack(alignment: .center, spacing: size.width * 0.05) {
            artwork(side: art)

            VStack(spacing: 28) {
                episodeInfo
                scrubber
                controls
                volumeRow
                bottomActions
            }
            .frame(maxWidth: min(size.width * 0.5, 520))
        }
        .padding(.horizontal, size.width * 0.05)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Shared chrome

    private func artwork(side: CGFloat) -> some View {
        PlayerArtworkView(imageURL: viewModel.imageURL, isPlaying: viewModel.isPlaying, size: side)
    }

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
/// only the scrubber, not the whole adaptive player layout.
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
