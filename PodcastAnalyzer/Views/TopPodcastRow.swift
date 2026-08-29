//
//  TopPodcastRow.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/3/14.
//


import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct TopPodcastRow: View {
  let podcast: AppleRSSPodcast
  let rank: Int
  let isSubscribed: Bool
  let onSubscribe: () -> Void

  @Environment(\.zoomNamespace) private var zoomNamespace

  var body: some View {
    NavigationLink(value: podcast) {
      HStack(spacing: 12) {
        // Rank
        Text("\(rank)")
          .font(.headline)
          .foregroundStyle(.secondary)
          .frame(width: 24)

        // Artwork - using CachedAsyncImage for better performance
        CachedArtworkImage(urlString: podcast.safeArtworkUrl, size: 56, cornerRadius: 8)

        // Info
        VStack(alignment: .leading, spacing: 2) {
          Text(podcast.name)
            .font(.subheadline)
            .fontWeight(.medium)
            .lineLimit(1)
            .foregroundStyle(.primary)

          Text(podcast.artistName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

          if let genres = podcast.genres, let first = genres.first {
            Text(first.name)
              .font(.caption2)
              .foregroundStyle(.blue)
          }
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 8)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .zoomSource(id: podcast.id, in: zoomNamespace)
    .contextMenu {
      // View episodes
      NavigationLink(value: podcast) {
        Label("View Episodes", systemImage: "list.bullet")
      }

      Divider()

      // Subscribe
      if isSubscribed {
        Label("Already Subscribed", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      } else {
        Button {
          onSubscribe()
        } label: {
          Label("Subscribe", systemImage: "plus.circle")
        }
      }

      // View on Apple Podcasts
      if let url = URL(string: podcast.url) {
        Link(destination: url) {
          Label("View on Apple Podcasts", systemImage: "link")
        }
      }

      Divider()

      // Copy name
      Button {
        PlatformClipboard.string = podcast.name
      } label: {
        Label("Copy Name", systemImage: "doc.on.doc")
      }

      // Share
      if let url = URL(string: podcast.url) {
        Button {
          PlatformShareSheet.share(url: url)
        } label: {
          Label("Share", systemImage: "square.and.arrow.up")
        }
      }
    }

    Divider()
  }
}