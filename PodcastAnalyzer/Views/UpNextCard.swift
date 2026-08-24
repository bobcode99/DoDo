//
//  UpNextCard.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/3/14.
//

import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct UpNextCard: View {
  let episode: LibraryEpisode
  let onPlay: () -> Void
  var reason: SuggestionReason = .none

  private var isQueued: Bool {
    if case .inQueue = reason { return true }
    return false
  }
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
            isCompact: true,
            episodeKey: observer.episodeKey
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
        .lineLimit(2, reservesSpace: true)
        .multilineTextAlignment(.leading)

      // Suggestion reason badge — reserves its row height even with no badge
      // (`Color.clear`) so every card in the carousel is the same height
      // instead of relying on a Spacer inside a hardcoded outer frame, which
      // squeezed the play button off the bottom once the title above started
      // reserving 2 lines unconditionally.
      Group {
        switch reason {
        case .inQueue, .inProgress, .starred, .downloaded:
          HStack(spacing: 3) {
            Image(systemName: reason.systemImage)
              .font(.system(size: 9))
            Text(reason.label)
              .font(.system(size: 10))
              .lineLimit(1)
          }
          // Queued rows are there because the user put them there — tint the
          // badge so explicit intent reads differently from an inferred reason.
          .foregroundStyle(isQueued ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        default:
          Color.clear
        }
      }
      .frame(height: 14, alignment: .leading)
      .padding(.top, 1)

      // Play button with progress - uses live audio manager state
      LivePlaybackButton(
        episode: episode,
        style: .compact,
        action: onPlay
      )
    }
    .frame(width: 140, alignment: .top)
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

// MARK: - Preview Mocks

private func mockUpNextEpisode(
  title: String,
  podcast: String = "The Swift Podcast",
  isStarred: Bool = false,
  isDownloaded: Bool = false,
  lastPlaybackPosition: TimeInterval = 0
) -> LibraryEpisode {
  LibraryEpisode(
    id: "\(podcast)\u{1F}\(title)",
    podcastTitle: podcast,
    imageURL: nil,
    language: "en",
    episodeInfo: PodcastEpisodeInfo(
      title: title,
      podcastEpisodeDescription: "A deep dive into async/await patterns",
      pubDate: Date(),
      audioURL: "https://example.com/episode.mp3",
      duration: 1800
    ),
    isStarred: isStarred,
    isDownloaded: isDownloaded,
    isCompleted: false,
    lastPlaybackPosition: lastPlaybackPosition,
    savedDuration: 1800
  )
}

#Preview("No Badge") {
  UpNextCard(
    episode: mockUpNextEpisode(title: "Understanding Swift Concurrency in Practice"),
    onPlay: {}
  )
  .padding()
  .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}

#Preview("In Progress") {
  UpNextCard(
    episode: mockUpNextEpisode(title: "The Daily", lastPlaybackPosition: 594),
    onPlay: {},
    reason: .inProgress(percentComplete: 33)
  )
  .padding()
  .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}

#Preview("Starred") {
  UpNextCard(
    episode: mockUpNextEpisode(title: "A Deep Dive Into Ambient Sound Design", isStarred: true),
    onPlay: {},
    reason: .starred
  )
  .padding()
  .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}

#Preview("In Queue") {
  UpNextCard(
    episode: mockUpNextEpisode(title: "Season Finale: What We Got Wrong"),
    onPlay: {},
    reason: .inQueue(position: 1)
  )
  .padding()
  .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}

/// A row of mixed 1-line and 2-line titles, badge and no-badge — the exact
/// layout the Up Next carousel renders, so a height regression that clips
/// the play button (or misaligns rows) shows up here instead of only in a
/// single-card preview.
#Preview("Carousel Row") {
  ScrollView(.horizontal) {
    HStack(spacing: 12) {
      UpNextCard(
        episode: mockUpNextEpisode(title: "The Daily", lastPlaybackPosition: 594),
        onPlay: {},
        reason: .inProgress(percentComplete: 33)
      )
      UpNextCard(
        episode: mockUpNextEpisode(title: "Think Baseball Is Boring? The Sabermetrics Revolution"),
        onPlay: {},
        reason: .newEpisode
      )
      UpNextCard(
        episode: mockUpNextEpisode(title: "Understanding Swift Concurrency in Practice", isStarred: true),
        onPlay: {},
        reason: .starred
      )
      UpNextCard(
        episode: mockUpNextEpisode(title: "Radiolab"),
        onPlay: {}
      )
    }
    .padding()
  }
  .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
