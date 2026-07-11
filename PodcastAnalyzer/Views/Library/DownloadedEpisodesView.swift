//
//  DownloadedEpisodesView.swift
//  PodcastAnalyzer
//
//  Downloaded episodes list (Sub-page)
//

import SwiftData
import SwiftUI

struct DownloadedEpisodesView: View {
  @Bindable var viewModel: LibraryViewModel
  let showEpisodeArtwork: Bool
  var podcastTitleFilter: String? = nil
  @Environment(\.modelContext) private var modelContext
  @State private var episodeModels: [String: EpisodeDownloadModel] = [:]
  @State private var refreshTask: Task<Void, Never>?

  var body: some View {
    Group {
      if displayedDownloadedEpisodes.isEmpty && displayedDownloadingEpisodes.isEmpty {
        emptyStateView
      } else {
        List {
          // Downloading Section
          if !displayedDownloadingEpisodes.isEmpty {
            Section {
              ForEach(displayedDownloadingEpisodes) { downloading in
                DownloadingEpisodeRow(episode: downloading)
                  .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
              }
            } header: {
              Text("Downloading")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .textCase(nil)
            }
          }

          // Downloaded Section
          if !displayedDownloadedEpisodes.isEmpty {
            Section {
              ForEach(displayedDownloadedEpisodes) { episode in
                EpisodeRowView(
                  libraryEpisode: episode,
                  episodeModel: episodeModels[episode.id],
                  showArtwork: showEpisodeArtwork,
                  onToggleStar: {
                    LibraryEpisodeActions.toggleStar(episode, episodeModels: &episodeModels, context: modelContext)
                    refreshTask?.cancel()
                    refreshTask = Task { await viewModel.refreshDownloadedEpisodes() }
                  },
                  onDownload: { LibraryEpisodeActions.downloadEpisode(episode) },
                  onDeleteRequested: {
                    LibraryEpisodeActions.deleteDownload(episode, episodeModels: episodeModels, context: modelContext)
                    refreshTask?.cancel()
                    refreshTask = Task { await viewModel.refreshDownloadedEpisodes() }
                  },
                  onTogglePlayed: {
                    LibraryEpisodeActions.togglePlayed(episode, episodeModels: &episodeModels, context: modelContext)
                    refreshTask?.cancel()
                    refreshTask = Task { await viewModel.refreshDownloadedEpisodes() }
                  }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
              }
            } header: {
              if !displayedDownloadingEpisodes.isEmpty {
                Text("Downloaded")
                  .font(.subheadline)
                  .fontWeight(.semibold)
                  .foregroundStyle(.primary)
                  .textCase(nil)
              }
            }
          }
        }
        .listStyle(.plain)
        .refreshable {
          await viewModel.refreshDownloadedEpisodes()
        }
      }
    }
    .navigationTitle(podcastTitleFilter ?? "Downloaded")
    .searchable(text: $viewModel.downloadedSearchText, prompt: "Search downloaded episodes")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear {
      viewModel.setModelContext(modelContext)
      episodeModels = LibraryEpisodeActions.batchFetchEpisodeModels(from: modelContext)
    }
    .task {
      await viewModel.refreshDownloadedEpisodes()
    }
    .task {
      for await _ in NotificationCenter.default.notifications(named: .episodeDownloadCompleted) {
        await viewModel.refreshDownloadedEpisodes()
        episodeModels = LibraryEpisodeActions.batchFetchEpisodeModels(from: modelContext)
      }
    }
    .onDisappear {
      refreshTask?.cancel()
    }
  }

  private var displayedDownloadedEpisodes: [LibraryEpisode] {
    guard let podcastTitleFilter else { return viewModel.filteredDownloadedEpisodes }
    return viewModel.filteredDownloadedEpisodes.filter { $0.podcastTitle == podcastTitleFilter }
  }

  private var displayedDownloadingEpisodes: [DownloadingEpisode] {
    guard let podcastTitleFilter else { return viewModel.downloadingEpisodes }
    return viewModel.downloadingEpisodes.filter { $0.podcastTitle == podcastTitleFilter }
  }

  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "arrow.down.circle")
        .font(.system(size: 50))
        .foregroundStyle(.secondary)
      Text("No Downloads")
        .font(.headline)
      Text("Downloaded episodes will appear here for offline listening")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
