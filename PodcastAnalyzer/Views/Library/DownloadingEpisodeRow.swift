//
//  DownloadingEpisodeRow.swift
//  PodcastAnalyzer
//
//  Created by JunNianLo on 2026/7/10.
//


import SwiftData
import SwiftUI

struct DownloadingEpisodeRow: View {
  let episode: DownloadingEpisode

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

      // Apple-style ring, no numbers. Live-polls in-flight progress so the
      // row stays current even between the parent's snapshot updates.
      if case .finishing = episode.state {
        ProgressView()
          .scaleEffect(0.7)
          .frame(width: 22, height: 22)
      } else {
        LiveDownloadProgressRing(episodeKey: episode.id, size: 22, lineWidth: 2.5, symbol: "arrow.down")
      }
    }
    .padding(.vertical, 4)
  }
}