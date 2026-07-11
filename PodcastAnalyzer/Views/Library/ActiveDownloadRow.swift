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

  private var statusText: String {
    switch episode.state {
    case .downloading(let progress):
      return "\(Int(progress * 100))%"
    case .finishing:
      return "Saving..."
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
      }

      Spacer()

      VStack(alignment: .trailing, spacing: 6) {
        Text(statusText)
          .font(.caption)
          .foregroundStyle(.blue)
          .fontWeight(.medium)

        if case .downloading = episode.state {
          Button("Cancel") {
            downloadManager.cancelDownload(
              episodeTitle: episode.episodeTitle,
              podcastTitle: episode.podcastTitle
            )
          }
          .font(.caption)
          .foregroundStyle(.red)
          .buttonStyle(.plain)
        }
      }
    }
    .padding(.vertical, 4)
  }
}
