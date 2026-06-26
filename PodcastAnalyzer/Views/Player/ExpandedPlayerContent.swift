import SwiftUI

/// iPhone (compact) expanded-player layout: a single centered column.
/// Composes the shared chrome from `PlayerChrome` so it stays in sync with the
/// iPad layout.
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
                    PlayerEpisodeInfoView(
                        viewModel: viewModel,
                        onNavigateToEpisodeDetail: onNavigateToEpisodeDetail,
                        onNavigateToPodcast: onNavigateToPodcast
                    )
                    .padding(.top, 24)
                }

                Spacer(minLength: 20)

                VStack(spacing: 32) {
                    PlayerScrubberBar(viewModel: viewModel)
                    PlayerControlsView(viewModel: viewModel)
                    PlayerVolumeRow()
                }

                Spacer(minLength: 32)

                PlayerBottomActionsView(
                    queueCount: viewModel.queue.count,
                    onNavigateToEpisodeDetail: onNavigateToEpisodeDetail,
                    onOpenQueue: onOpenQueue
                )
                .padding(.bottom, 40)
            }
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center)
        }
    }
}
