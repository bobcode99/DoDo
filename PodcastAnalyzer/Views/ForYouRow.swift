//
//  ForYouRow.swift
//  PodcastAnalyzer
//
//  Created by JunNianLo on 2026/5/16.
//
//  Was a 140pt-wide card in a horizontal carousel. The model's reason is the
//  only thing on it that a plain "newest unplayed" sort could not produce, and
//  at 140pt it had roughly 40 characters of room — so a twelve-word reason
//  always arrived as "personal interest in tech…". A full-width row gives the
//  reason ~240pt, which fits the whole thing, and For You only ever returns
//  three to five picks, so a vertical list costs no scrolling.
//

import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ForYouRow: View {
  let episode: LibraryEpisode
  /// Why the model picked this one. nil when it returned fewer reasons than
  /// picks — the row then reads like any other episode row.
  var reason: String? = nil
  @Environment(\.modelContext) private var modelContext
  @State private var statusObserver: EpisodeStatusObserver?

  private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }

  private func playEpisode() {
    guard episode.episodeInfo.audioURL != nil else { return }
    guard let observer = statusObserver else { return }

    let playbackEpisode = PlaybackEpisode(
      id: EpisodeKeyUtils.makeKey(podcastTitle: episode.podcastTitle, episodeTitle: episode.episodeInfo.title),
      title: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle,
      audioURL: observer.playbackURL,
      imageURL: episode.imageURL,
      episodeDescription: episode.episodeInfo.podcastEpisodeDescription,
      pubDate: episode.episodeInfo.pubDate,
      duration: episode.episodeInfo.duration,
      guid: episode.episodeInfo.guid
    )

    // Completed episodes always restart from 0 — see EpisodeRowView.playAction().
    let startTime = episode.isCompleted ? 0 : episode.lastPlaybackPosition
    audioManager.play(
      episode: playbackEpisode,
      audioURL: observer.playbackURL,
      startTime: startTime,
      imageURL: episode.imageURL ?? "",
      useDefaultSpeed: startTime == 0
    )
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      ZStack(alignment: .bottomTrailing) {
        CachedArtworkImage(urlString: episode.imageURL, size: 72, cornerRadius: 8)

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

      VStack(alignment: .leading, spacing: 3) {
        Text(episode.podcastTitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Text(episode.episodeInfo.title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        if let reason, !reason.isEmpty {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            // Only the glyph carries the accent. The reason itself stays
            // secondary so it reads as a caption rather than competing with the
            // episode title, and so it survives any accent the user picks.
            Image(systemName: "sparkles")
              .font(.caption2)
              .foregroundStyle(.tint)
            Text(reason)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }
          .padding(.top, 1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      LivePlaybackButton(
        episode: episode,
        style: .compact,
        action: playEpisode
      )
    }
    .padding(.vertical, 8)
    .contentShape(.rect)
    .onAppear {
      if statusObserver == nil {
        statusObserver = EpisodeStatusObserver(episode: episode)
      }
      statusObserver?.setModelContext(modelContext)
    }
    .onDisappear {
      statusObserver?.cleanup()
    }
  }
}
