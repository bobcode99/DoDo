//
//  MacLibraryEpisodeRow.swift
//  PodcastAnalyzer
//
//  macOS Library — episode row content (image, title, play button)
//

#if os(macOS)
import SwiftUI

struct MacLibraryEpisodeRow: View {
  let episode: PodcastEpisodeInfo
  let podcastTitle: String
  let podcastImageURL: String
  let podcastLanguage: String

  var body: some View {
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
        Button(action: playEpisode) {
          Label("Play", systemImage: "play.fill")
            .labelStyle(.iconOnly)
            .font(.title3)
            .frame(width: 32, height: 32)
            // Same reason as the sidebar badge: a white glyph on a `.tint`
            // fill disappears when the accent resolves to white.
            .accentFilled(in: .circle)
        }
        .buttonStyle(.plain)
        .help("Play")
      }
    }
    .padding(.vertical, 4)
  }

  private func playEpisode() {
    Self.play(episode, podcastTitle: podcastTitle, imageURL: episode.imageURL ?? podcastImageURL)
  }
}

// MARK: - Playback

extension MacLibraryEpisodeRow {
  /// The local file when downloaded, otherwise the feed URL. Nil without audio.
  static func playbackEpisode(
    for episode: PodcastEpisodeInfo, podcastTitle: String, imageURL: String
  ) -> PlaybackEpisode? {
    let statusChecker = EpisodeStatusChecker(episode: episode, podcastTitle: podcastTitle)
    let playbackURL = statusChecker.playbackURL
    guard !playbackURL.isEmpty else { return nil }
    return PlaybackEpisode(
      id: statusChecker.episodeKey,
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: playbackURL,
      imageURL: imageURL,
      episodeDescription: episode.podcastEpisodeDescription,
      pubDate: episode.pubDate,
      duration: episode.duration,
      guid: episode.guid
    )
  }

  static func play(_ episode: PodcastEpisodeInfo, podcastTitle: String, imageURL: String) {
    guard let playbackEpisode = playbackEpisode(
      for: episode, podcastTitle: podcastTitle, imageURL: imageURL
    ) else { return }
    // Live store, not a row snapshot (can be stale); returns 0 for completed
    // episodes — see EpisodeRowView.playAction().
    EnhancedAudioManager.shared.play(
      episode: playbackEpisode,
      audioURL: playbackEpisode.audioURL,
      startTime: PlaybackStateCoordinator.savedPlaybackPosition(
        podcastTitle: podcastTitle, episodeTitle: episode.title),
      imageURL: imageURL,
      useDefaultSpeed: true
    )
  }
}
#endif
