//
//  EpisodeRow.swift
//  DoDoWatch
//
//  Artwork beside title and show — the row shape of the system Podcasts list.
//

import SwiftUI

struct EpisodeRow: View {
  let title: String
  let subtitle: String
  let imageURL: String?

  var body: some View {
    HStack(spacing: 8) {
      WatchArtwork(urlString: imageURL ?? "", size: 32)
      VStack(alignment: .leading, spacing: 1) {
        Text(title)
          .font(.footnote)
          .lineLimit(2)
        Text(subtitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }
}
