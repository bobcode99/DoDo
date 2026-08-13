//
//  LibrarySearchRows.swift
//  PodcastAnalyzer
//
//  Search result rows for the Library tab: a subscribed podcast and a
//  matching episode. Rows are plain buttons — the parent decides how to
//  navigate (SearchView dismisses the tab-bar search keyboard before
//  pushing; see PodcastSearchView.navigate).
//

import SwiftUI

struct LibraryPodcastRow: View {
    let podcastModel: PodcastInfoModel
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                CachedArtworkImage(urlString: podcastModel.imageURL, size: 56, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(podcastModel.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text("Show · \(podcastModel.episodeCount) episodes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LibraryEpisodeRow: View {
    let episode: PodcastEpisodeInfo
    let podcastTitle: String
    let podcastImageURL: String
    let podcastLanguage: String
    let onPlay: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                CachedArtworkImage(urlString: episode.imageURL ?? podcastImageURL, size: 56, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if let date = episode.pubDate {
                            Text(Formatters.formatDate(date))
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

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
