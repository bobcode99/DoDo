//
//  EpisodeMiniHeader.swift
//  PodcastAnalyzer
//
//  Compact context strip used by the macOS sub-pages (Transcript / AI) so the
//  reader keeps episode context while the main content scrolls underneath.
//

import SwiftUI

struct EpisodeMiniHeader: View {
    @Bindable var viewModel: EpisodeDetailViewModel

    var body: some View {
        HStack(spacing: 12) {
            CachedArtworkImage(
                urlString: viewModel.imageURLString,
                size: 48,
                cornerRadius: 8
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(viewModel.podcastTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LivePlaybackButton(
                episodeTitle: viewModel.title,
                podcastTitle: viewModel.podcastTitle,
                duration: viewModel.savedDuration,
                formattedDuration: viewModel.formattedDuration,
                lastPlaybackPosition: viewModel.lastPlaybackPosition,
                playbackProgress: viewModel.playbackProgress,
                isCompleted: viewModel.isCompleted,
                onPlay: { viewModel.playAction() },
                style: .iconOnly,
                isDisabled: viewModel.isPlayDisabled
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
