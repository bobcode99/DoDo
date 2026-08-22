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

  private var audioManager: EnhancedAudioManager { EnhancedAudioManager.shared }

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
        Button(action: {
          playEpisode()
        }) {
          Image(systemName: "play.fill")
            .font(.title3)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(.tint)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 4)
  }

  private func playEpisode() {
    guard let audioURL = episode.audioURL else { return }

    let playbackEpisode = PlaybackEpisode(
      id: "\(podcastTitle)\u{1F}\(episode.title)",
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: audioURL,
      imageURL: episode.imageURL ?? podcastImageURL,
      episodeDescription: episode.podcastEpisodeDescription,
      pubDate: episode.pubDate,
      duration: episode.duration,
      guid: episode.guid
    )

    audioManager.play(
      episode: playbackEpisode,
      audioURL: audioURL,
      startTime: 0,
      imageURL: episode.imageURL ?? podcastImageURL,
      useDefaultSpeed: true
    )
  }
}
#endif
