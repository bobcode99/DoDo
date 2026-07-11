//
//  DownloadedPodcastCell.swift
//  PodcastAnalyzer
//

import SwiftUI

struct DownloadedPodcastCell: View {
  let title: String
  let imageURL: String?
  let downloadCount: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CachedAsyncImage(url: URL(string: imageURL ?? "")) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Color.gray.opacity(0.2)
          .overlay(ProgressView().scaleEffect(0.5))
      }
      .aspectRatio(1, contentMode: .fit)
      .clipShape(.rect(cornerRadius: 10))
      .clipped()

      Text(title)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2)
        .foregroundStyle(.primary)

      Text("\(downloadCount) downloaded")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }
}
