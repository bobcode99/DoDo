//
//  UpNextListView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/3/14.
//

import SwiftData
import SwiftUI

// MARK: - View

struct UpNextListView: View {
  let episodes: [LibraryEpisode]
  let onToggleStar: (LibraryEpisode) -> Void
  let onTogglePlayed: (LibraryEpisode) -> Void
  let onDownload: (LibraryEpisode) -> Void
  let onDeleteDownload: (LibraryEpisode) -> Void
  let onDismiss: (LibraryEpisode) -> Void

  @Environment(\.modelContext) private var modelContext
  @State private var episodeToDelete: LibraryEpisode?
  @State private var showDeleteConfirmation = false
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]

  // Access singleton directly to determine now-playing without creating a timer
  private var audioManager: EnhancedAudioManager { .shared }

  // Episodes arrive pre-ordered by HomeViewModel as a single composite-scored list:
  // now-playing pinned at position 0, then everything else by score (which already
  // privileges fresh-from-engaged > in-progress > suggestions).
  private var nowPlayingId: String? { audioManager.currentEpisode?.id }

  var body: some View {
    List {
      ForEach(episodes) { episode in
        episodeRow(episode)
      }
    }
    .listStyle(.plain)
    .onAppear { batchFetchEpisodeModels() }
    .onChange(of: episodes.count) { _, _ in
      batchFetchEpisodeModels()
    }
    .animation(.default, value: episodes.map(\.id))
    .navigationTitle("Up Next")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .confirmationDialog(
      "Delete Download",
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let episode = episodeToDelete {
          onDeleteDownload(episode)
        }
        episodeToDelete = nil
      }
      Button("Cancel", role: .cancel) {
        episodeToDelete = nil
      }
    } message: {
      Text("Are you sure you want to delete this downloaded episode?")
    }
  }

  @ViewBuilder
  private func episodeRow(_ episode: LibraryEpisode) -> some View {
    EpisodeRowView(
      libraryEpisode: episode,
      episodeModel: episodeModels[episode.id],
      onToggleStar: { onToggleStar(episode) },
      onDownload: { onDownload(episode) },
      onDeleteRequested: {
        episodeToDelete = episode
        showDeleteConfirmation = true
      },
      onTogglePlayed: { onTogglePlayed(episode) },
      onRemoveFromUpNext: episode.id == nowPlayingId ? nil : { onDismiss(episode) }
    )
    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
  }

  // MARK: - Episode Model Fetch

  private func batchFetchEpisodeModels() {
    let descriptor = FetchDescriptor<EpisodeDownloadModel>()
    guard let results = try? modelContext.fetch(descriptor) else { return }
    var models: [String: EpisodeDownloadModel] = [:]
    for model in results {
      models[model.id] = model
    }
    episodeModels = models
  }
}

// MARK: - Preview

#Preview {
  let mockEpisodes = [
    LibraryEpisode(
      id: "podcast1\u{1F}episode1",
      podcastTitle: "The Swift Podcast",
      imageURL: nil,
      language: "en",
      episodeInfo: PodcastEpisodeInfo(
        title: "Understanding Swift Concurrency",
        podcastEpisodeDescription: "A deep dive into async/await",
        pubDate: Date(),
        audioURL: "https://example.com/ep1.mp3",
        duration: 1800
      ),
      isStarred: false,
      isDownloaded: false,
      isCompleted: false,
      lastPlaybackPosition: 0,
      savedDuration: 0
    ),
    LibraryEpisode(
      id: "podcast2\u{1F}episode2",
      podcastTitle: "Accidental Tech Podcast",
      imageURL: nil,
      language: "en",
      episodeInfo: PodcastEpisodeInfo(
        title: "M5 MacBook Pro Review",
        podcastEpisodeDescription: "We review the latest hardware",
        pubDate: Date().addingTimeInterval(-86400),
        audioURL: "https://example.com/ep2.mp3",
        duration: 5400
      ),
      isStarred: true,
      isDownloaded: true,
      isCompleted: false,
      lastPlaybackPosition: 1200,
      savedDuration: 5400
    )
  ]

  NavigationStack {
    UpNextListView(
      episodes: mockEpisodes,
      onToggleStar: { _ in },
      onTogglePlayed: { _ in },
      onDownload: { _ in },
      onDeleteDownload: { _ in },
      onDismiss: { _ in }
    )
  }
  .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
