//
//  ForYouCard.swift
//  PodcastAnalyzer
//
//  Created by JunNianLo on 2026/5/16.
//


import NukeUI
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ForYouCard: View {
  let episode: LibraryEpisode
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

    audioManager.play(
      episode: playbackEpisode,
      audioURL: observer.playbackURL,
      startTime: episode.lastPlaybackPosition,
      imageURL: episode.imageURL ?? "",
      useDefaultSpeed: episode.lastPlaybackPosition == 0
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Episode artwork
      ZStack(alignment: .bottomTrailing) {
        CachedArtworkImage(urlString: episode.imageURL, size: 140, cornerRadius: 12)

        // Status icons overlay
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

      Spacer(minLength: 0)

      // Play button
      LivePlaybackButton(
        episode: episode,
        style: .compact,
        action: playEpisode
      )
    }
    .frame(width: 140, height: 258, alignment: .top)
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