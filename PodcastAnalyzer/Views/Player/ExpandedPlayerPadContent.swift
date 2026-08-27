import SwiftUI

/// iPad (regular) expanded-player layout. Uses the same shared chrome as the
/// iPhone layout (`PlayerChrome`, `PlayerArtworkView`, `PlayerEpisodeInfoView`,
/// `PlayerControlsView`, `PlayerBottomActionsView`) — only the arrangement
/// differs. Orientation is read from `verticalSizeClass` (no GeometryReader):
/// landscape is `.compact`, portrait is `.regular`.
struct ExpandedPlayerPadContent: View {
    let viewModel: ExpandedPlayerViewModel
    let onNavigateToEpisodeDetail: () -> Void
    let onNavigateToPodcast: () -> Void
    let onOpenQueue: () -> Void

    @Environment(\.verticalSizeClass) private var vSize

    var body: some View {
        ScrollView {
            Group {
                if vSize == .compact {
                    landscape
                } else {
                    portrait
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Portrait: centered column, larger artwork

    private var portrait: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                artwork(side: 360)
                    .padding(.top, 24)
                episodeInfo
                    .padding(.top, 28)
            }

            Spacer(minLength: 32)

            VStack(spacing: 36) {
                PlayerScrubberBar(viewModel: viewModel)
                PlayerControlsView(viewModel: viewModel)
                PlayerVolumeRow()
            }

            Spacer(minLength: 40)

            bottomActions
                .padding(.bottom, 48)
        }
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, alignment: .center)
    }

    // MARK: - Landscape: artwork left, controls right

    private var landscape: some View {
        HStack(alignment: .center, spacing: 48) {
            artwork(side: 300)

            VStack(spacing: 28) {
                episodeInfo
                PlayerScrubberBar(viewModel: viewModel)
                PlayerControlsView(viewModel: viewModel)
                PlayerVolumeRow()
                bottomActions
            }
            .frame(maxWidth: 460)
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 32)
        .frame(maxWidth: 920)
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, alignment: .center)
    }

    // MARK: - Shared pieces

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

    private var bottomActions: some View {
        PlayerBottomActionsView(
            queueCount: viewModel.queue.count,
            onNavigateToEpisodeDetail: onNavigateToEpisodeDetail,
            onOpenQueue: onOpenQueue
        )
    }
}
