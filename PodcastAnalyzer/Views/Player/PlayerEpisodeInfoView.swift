import SwiftUI

struct PlayerEpisodeInfoView: View {
    var viewModel: ExpandedPlayerViewModel
    let onNavigateToEpisodeDetail: () -> Void
    let onNavigateToPodcast: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .center, spacing: 4) {
                    Text(viewModel.episodeTitle)
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    Button(action: onNavigateToPodcast) {
                        Text(viewModel.podcastTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.leading, 44)

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
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                }
                .frame(width: 48, height: 48)
            }
            .padding(.horizontal, 20)

            if let date = viewModel.episodeDate {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
        }
    }
}
