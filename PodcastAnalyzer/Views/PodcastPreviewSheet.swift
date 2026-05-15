//
//  PodcastPreviewSheet.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/3/14.
//

import NukeUI
import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct PodcastPreviewSheet: View {
  let podcast: AppleRSSPodcast
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @State private var viewModel = PodcastSubscriptionViewModel()

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          artworkSection
          titleSection
          genresSection
          subscribeSection
          applePodcastsLink
        }
        .padding()
      }
      .navigationTitle("Podcast")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            dismiss()
          }
        }
      }
      .onChange(of: viewModel.subscriptionSuccess) { _, success in
        if success {
          NotificationCenter.default.post(name: .podcastDataChanged, object: nil)
          dismiss()
        }
      }
      .onDisappear {
        viewModel.cleanup()
      }
    }
  }

  // MARK: - Artwork

  private var artworkSection: some View {
    CachedArtworkImage(urlString: podcast.safeArtworkUrl, size: 200, cornerRadius: 16)
      .shadow(radius: 8)
  }

  // MARK: - Title

  private var titleSection: some View {
    VStack(spacing: 4) {
      Text(podcast.name)
        .font(.title2)
        .fontWeight(.bold)
        .multilineTextAlignment(.center)

      Text(podcast.artistName)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Genres

  @ViewBuilder
  private var genresSection: some View {
    if let genres = podcast.genres {
      HStack {
        ForEach(genres, id: \.genreId) { genre in
          Text(genre.name)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(.blue)
            .glassEffect(.regular.tint(.blue), in: .rect(cornerRadius: 12))
        }
      }
    }
  }

  // MARK: - Subscribe

  @ViewBuilder
  private var subscribeSection: some View {
    if viewModel.isAlreadySubscribed(podcast, in: modelContext) {
      HStack {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
        Text("Already Subscribed")
          .font(.headline)
          .foregroundStyle(.green)
      }
      .frame(maxWidth: .infinity)
      .padding()
      .glassEffect(.regular.tint(.green), in: .rect(cornerRadius: 12))
      .padding(.horizontal)
    } else if viewModel.isSubscribing {
      ProgressView("Subscribing...")
    } else if viewModel.subscriptionError != nil {
      VStack(spacing: 8) {
        Text("Failed to subscribe")
          .foregroundStyle(.red)
        Button("Try Again") {
          viewModel.subscribeToPodcast(podcast, context: modelContext)
        }
      }
    } else {
      Button(action: {
        viewModel.subscribeToPodcast(podcast, context: modelContext)
      }) {
        Label("Subscribe", systemImage: "plus.circle.fill")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding()
      }
      .buttonStyle(.glassProminent)
      .padding(.horizontal)
    }
  }

  // MARK: - Apple Podcasts Link

  @ViewBuilder
  private var applePodcastsLink: some View {
    if let url = URL(string: podcast.url) {
      Link(destination: url) {
        Label("View on Apple Podcasts", systemImage: "link")
          .font(.subheadline)
      }
      .padding(.top, 8)
    }
  }
}

// MARK: - Preview

#Preview {
  let mockPodcast = AppleRSSPodcast(
    id: "1234567890",
    artistName: "Apple Inc.",
    name: "The Talk Show With John Gruber",
    artworkUrl100: nil,
    url: "https://podcasts.apple.com/podcast/id1234567890",
    genres: [
      AppleRSSGenre(genreId: "1318", name: "Technology", url: ""),
      AppleRSSGenre(genreId: "1324", name: "Society & Culture", url: "")
    ],
    contentAdvisoryRating: nil,
    releaseDate: nil,
    kind: nil
  )

  PodcastPreviewSheet(podcast: mockPodcast)
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
