//
//  ActiveDownloadRow.swift
//  PodcastAnalyzer
//
//  Row with cancel button for an in-progress download.
//

import SwiftUI

struct ActiveDownloadRow: View {
  let episode: DownloadingEpisode
  let downloadManager: DownloadManager

  var body: some View {
    HStack(spacing: 12) {
      CachedAsyncImage(url: URL(string: episode.imageURL ?? "")) { image in
        image
          .resizable()
          .aspectRatio(contentMode: .fill)
      } placeholder: {
        Rectangle()
          .fill(Color.gray.opacity(0.2))
          .overlay(
            Image(systemName: "music.note")
              .foregroundStyle(.gray)
          )
      }
      .frame(width: 56, height: 56)
      .clipShape(.rect(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 4) {
        Text(episode.episodeTitle)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(2)

        Text(episode.podcastTitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer()

      // Apple-style: tap the ring to cancel (stop symbol inside), no numbers.
      if case .finishing = episode.state {
        ProgressView()
          .scaleEffect(0.7)
          .frame(width: 22, height: 22)
      } else {
        Button {
          downloadManager.cancelDownload(
            episodeTitle: episode.episodeTitle,
            podcastTitle: episode.podcastTitle
          )
        } label: {
          LiveDownloadProgressRing(episodeKey: episode.id, size: 22, lineWidth: 2.5, symbol: "stop.fill")
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 4)
  }
}
