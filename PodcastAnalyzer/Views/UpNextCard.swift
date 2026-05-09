//
//  UpNextCard.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/3/14.
//

import NukeUI
import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct UpNextCard: View {
  let episode: LibraryEpisode
  let onPlay: () -> Void
  var reason: SuggestionReason = .none
  @Environment(\.modelContext) private var modelContext
  @State private var statusObserver: EpisodeStatusObserver?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Episode artwork
      ZStack(alignment: .bottomTrailing) {
        CachedArtworkImage(urlString: episode.imageURL, size: 140, cornerRadius: 12)

        // Status icons overlay (reactive)
        if let observer = statusObserver {
          EpisodeStatusIcons(
            isStarred: episode.isStarred,
            isDownloaded: observer.isDownloaded,
            hasTranscript: observer.hasTranscript,
            hasAIAnalysis: observer.hasAIAnalysis,
            isDownloading: observer.isDownloading,
            downloadProgress: observer.downloadProgress,
            isTranscribing: observer.isTranscribing,
            isCompact: true
          )
        }
      }

      // Podcast title
      Text(episode.podcastTitle)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      // Episode title
      Text(episode.episodeInfo.title)
        .font(.subheadline)
        .fontWeight(.medium)
        .lineLimit(2)
        .multilineTextAlignment(.leading)

      // Suggestion reason badge
      switch reason {
      case .inProgress, .starred, .downloaded:
        HStack(spacing: 3) {
          Image(systemName: reason.systemImage)
            .font(.system(size: 9))
          Text(reason.label)
            .font(.system(size: 10))
            .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.top, 1)
      default:
        Spacer(minLength: 0)
      }

      // Play button with progress - uses live audio manager state
      LivePlaybackButton(
        episode: episode,
        style: .compact,
        action: onPlay
      )
    }
    .frame(width: 140, height: 258, alignment: .top)
    .task(id: episode.id) {
      let observer = EpisodeStatusObserver(episode: episode)
      observer.setModelContext(modelContext)
      statusObserver = observer
    }
    .onDisappear {
      statusObserver?.cleanup()
    }
  }
}

#Preview {
  let mockEpisode = LibraryEpisode(
    id: "preview_podcast\u{1F}preview_episode",
    podcastTitle: "The Swift Podcast",
    imageURL: nil,
    language: "en",
    episodeInfo: PodcastEpisodeInfo(
      title: "Understanding Swift Concurrency in Practice",
      podcastEpisodeDescription: "A deep dive into async/await patterns",
      pubDate: Date(),
      audioURL: "https://example.com/episode.mp3",
      duration: 1800
    ),
    isStarred: true,
    isDownloaded: false,
    isCompleted: false,
    lastPlaybackPosition: 450,
    savedDuration: 1800
  )

  UpNextCard(episode: mockEpisode, onPlay: {})
    .padding()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
