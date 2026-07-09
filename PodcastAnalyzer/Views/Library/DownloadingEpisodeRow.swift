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

  private var statusText: String {
    switch episode.state {
    case .downloading(let progress):
      return "\(Int(progress * 100))%"
    case .finishing:
      return "Finishing..."
    default:
      return ""
    }
  }

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

        ProgressView(value: episode.progress)
          .progressViewStyle(.linear)
          .tint(.blue)
          .frame(height: 4)
      }

      Spacer()

      Text(statusText)
        .font(.caption)
        .foregroundStyle(.blue)
        .fontWeight(.medium)
    }
    .padding(.vertical, 4)
  }
}