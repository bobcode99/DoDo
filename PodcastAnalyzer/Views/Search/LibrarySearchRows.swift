//
//  LibrarySearchRows.swift
//  PodcastAnalyzer
//
//  Search result rows for the Library tab: a subscribed podcast and a
//  matching episode. Both push value-based routes — this list lives in a
//  path-bound NavigationStack, and a view-destination NavigationLink push
//  is invisible to the path, which breaks value links (transcript, AI
//  insights) inside the pushed screen.
//

import SwiftUI

struct LibraryPodcastRow: View {
    let podcastModel: PodcastInfoModel

    var body: some View {
        NavigationLink(value: PodcastBrowseRoute(podcastModel: podcastModel)) {
            HStack(spacing: 12) {
                CachedArtworkImage(urlString: podcastModel.podcastInfo.imageURL, size: 56, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(podcastModel.podcastInfo.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text("Show · \(podcastModel.podcastInfo.episodes.count) episodes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 4)
        }
        .contentShape(Rectangle())
    }
}

struct LibraryEpisodeRow: View {
    let episode: PodcastEpisodeInfo
    let podcastTitle: String
    let podcastImageURL: String
    let podcastLanguage: String
    let onPlay: () -> Void

    var body: some View {
        NavigationLink(value: EpisodeDetailRoute(
            episode: episode,
            podcastTitle: podcastTitle,
            fallbackImageURL: podcastImageURL,
            podcastLanguage: podcastLanguage
        )) {
            HStack(spacing: 12) {
                CachedArtworkImage(urlString: episode.imageURL ?? podcastImageURL, size: 56, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if let date = episode.pubDate {
                            Text(date.formatted(date: .abbreviated, time: .omitted))
                        }
                        if let duration = episode.formattedDuration {
                            Text("·")
                            Text(duration)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    Text(episode.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                Spacer()

                if episode.audioURL != nil {
                    Button(action: onPlay) {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.purple)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .contentShape(Rectangle())
    }
}
