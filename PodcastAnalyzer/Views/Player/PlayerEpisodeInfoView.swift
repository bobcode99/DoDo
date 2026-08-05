import SwiftUI

struct PlayerEpisodeInfoView: View {
    var viewModel: ExpandedPlayerViewModel
    let onNavigateToEpisodeDetail: () -> Void
    let onNavigateToPodcast: () -> Void

    var body: some View {
        // Left-aligned title block with the overflow menu on the trailing edge —
        // the arrangement Apple Podcasts and Spotify both use. The old centered
        // column needed a 44pt leading pad to fake optical centering against the
        // menu button, which broke as soon as the title wrapped or the width
        // changed.
        VStack(alignment: .leading, spacing: 6) {
            if let date = viewModel.episodeDate {
                Text(Formatters.formatDate(date))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    MarqueeText(
                        text: viewModel.episodeTitle,
                        font: .title3,
                        fontWeight: .bold,
                        alignment: .leading
                    )
                    .foregroundStyle(.primary)

                    Button(action: onNavigateToPodcast) {
                        Text(viewModel.podcastTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                Menu {
                    Section {
                        Button(
                            "Play Next",
                            systemImage: "text.line.first.and.arrowtriangle.forward",
                            action: viewModel.playNextCurrentEpisode
                        )
                        Button(
                            "Share Episode...",
                            systemImage: "square.and.arrow.up",
                            action: viewModel.shareEpisode
                        )
                    }
                    Section {
                        Button(
                            viewModel.isStarred ? "Unstar Episode" : "Star Episode",
                            systemImage: viewModel.isStarred ? "star.fill" : "star",
                            action: viewModel.toggleStar
                        )
                        if viewModel.hasLocalAudio {
                            Button(
                                "Remove Download",
                                systemImage: "minus.circle",
                                role: .destructive,
                                action: viewModel.deleteDownload
                            )
                        } else {
                            Button(
                                "Download Episode",
                                systemImage: "arrow.down.circle",
                                action: viewModel.startDownload
                            )
                        }
                    }
                    Section {
                        Button(
                            "View Episode Description",
                            systemImage: "doc.text",
                            action: onNavigateToEpisodeDetail
                        )
                        Button(
                            "Go to Show",
                            systemImage: "square.stack",
                            action: onNavigateToPodcast
                        )
                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 28))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("More options")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
    }
}
