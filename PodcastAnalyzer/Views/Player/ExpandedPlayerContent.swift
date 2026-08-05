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
            // One 32pt gutter for every row (the pieces used to mix 20/24/32/40,
            // so nothing lined up vertically), and the transport sits tight under
            // the scrubber it controls — the grouping Apple Podcasts and Spotify
            // both use — with the volume and secondary actions pushed further out.
            VStack(spacing: 0) {
                PlayerArtworkView(imageURL: viewModel.imageURL, isPlaying: viewModel.isPlaying)
                    .padding(.top, 12)

                Spacer(minLength: 28)

                PlayerEpisodeInfoView(
                    viewModel: viewModel,
                    onNavigateToEpisodeDetail: onNavigateToEpisodeDetail,
                    onNavigateToPodcast: onNavigateToPodcast
                )

                Spacer(minLength: 24)

                VStack(spacing: 20) {
                    PlayerScrubberBar(viewModel: viewModel)
                    PlayerControlsView(viewModel: viewModel)
                }

                Spacer(minLength: 28)

                PlayerVolumeRow()

                Spacer(minLength: 28)

                PlayerBottomActionsView(
                    queueCount: viewModel.queue.count,
                    onNavigateToEpisodeDetail: onNavigateToEpisodeDetail,
                    onOpenQueue: onOpenQueue
                )
                .padding(.bottom, 32)
            }
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center)
        }
    }
}
