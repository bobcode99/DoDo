//
//  TranscriptSearchViews.swift
//  PodcastAnalyzer
//
//  Transcript search result row views, extracted from SearchView.
//

import SwiftUI

// MARK: - Transcript Result Row

struct TranscriptResultRow: View {
    let result: TranscriptSearchResult

    var body: some View {
        NavigationLink(value: EpisodeDetailRoute(
            episode: result.episode,
            podcastTitle: result.podcastTitle,
            fallbackImageURL: result.podcastImageURL,
            podcastLanguage: result.podcastLanguage
        )) {
            HStack(spacing: 12) {
                CachedArtworkImage(urlString: result.podcastImageURL, size: 56, cornerRadius: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.episode.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                    HStack {
                        Text(result.podcastTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text("^[\(result.matchCount) match](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(result.snippets) { match in
                        TranscriptSnippetRow(match: match, result: result)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .contentShape(.rect)
    }
}

// MARK: - Transcript Snippet Row

struct TranscriptSnippetRow: View {
    let match: TranscriptMatch
    let result: TranscriptSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            TimestampLink(
                text: TimestampUtils.formatSeconds(match.timestamp),
                seconds: match.timestamp,
                onPlay: { playFromTimestamp() },
                onShare: { shareTimestamp() }
            )
            .frame(minWidth: 36, alignment: .trailing)
            Text(match.text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func playFromTimestamp() {
        let episode = result.episode
        let podcastTitle = result.podcastTitle
        let imageURL = result.podcastImageURL
        guard let audioURL = episode.audioURL else { return }
        let playbackEpisode = PlaybackEpisode(
            id: "\(podcastTitle)\u{1F}\(episode.title)",
            title: episode.title,
            podcastTitle: podcastTitle,
            audioURL: audioURL,
            imageURL: episode.imageURL ?? imageURL,
            episodeDescription: episode.podcastEpisodeDescription,
            pubDate: episode.pubDate,
            duration: episode.duration,
            guid: episode.guid
        )
        EnhancedAudioManager.shared.play(
            episode: playbackEpisode,
            audioURL: audioURL,
            startTime: match.timestamp,
            imageURL: episode.imageURL ?? imageURL,
            useDefaultSpeed: true
        )
    }

    private func shareTimestamp() {
        let label = "\(result.podcastTitle) – \(result.episode.title) [\(TimestampUtils.formatSeconds(match.timestamp))]"
        PlatformClipboard.string = label
    }
}

// MARK: - Transcript Search Key

struct TranscriptSearchKey: Hashable {
    let tab: SearchTab
    let query: String
}
