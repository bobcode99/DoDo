//
//  ApplePodcastRow.swift
//  PodcastAnalyzer
//
//  Search result row for an Apple Podcasts directory hit, with an inline
//  subscribe button.
//

import SwiftUI

struct ApplePodcastRow: View {
    let podcast: Podcast
    let isSubscribed: Bool
    let onSubscribe: () -> Void

    @State private var isSubscribing = false

    var body: some View {
        HStack(spacing: 12) {
            CachedArtworkImage(urlString: podcast.artworkUrl100, size: 56, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(podcast.collectionName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text("Show · \(podcast.artistName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Subscribe button or checkmark
            if isSubscribed {
                Image(systemName: "checkmark")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            } else if isSubscribing {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button("Subscribe", systemImage: "plus") {
                    isSubscribing = true
                    onSubscribe()
                    // Reset after a delay (subscription will update via @Query)
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        isSubscribing = false
                    }
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.blue)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
