//
//  DownloadedViews.swift
//  PodcastAnalyzer
//
//  Downloaded podcasts grid, cells, episode list, and downloading row for Library.
//

import SwiftData
import SwiftUI

// MARK: - Downloaded Podcasts Grid View (Sub-page)

struct DownloadedPodcastsGridView: View {
  @Bindable var viewModel: LibraryViewModel
  @Environment(\.modelContext) private var modelContext

  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12)
  ]

  var body: some View {
    Group {
      if viewModel.podcastsWithDownloads.isEmpty && viewModel.downloadingEpisodes.isEmpty {
        VStack(spacing: 16) {
          Image(systemName: "arrow.down.circle")
            .font(.system(size: 50))
            .foregroundStyle(.secondary)
          Text("No Downloads")
            .font(.headline)
          Text("Downloaded episodes will appear here")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 20) {
            // MARK: - Downloading Section
            if !viewModel.downloadingEpisodes.isEmpty {
              ActiveDownloadsSectionCard(viewModel: viewModel)
                .padding(.horizontal)
            }

            // MARK: - Downloaded Podcasts Grid
            if !viewModel.podcastsWithDownloads.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Text("Podcasts")
                  .font(.subheadline)
                  .fontWeight(.semibold)
                  .foregroundStyle(.secondary)
                  .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 16) {
                  ForEach(viewModel.podcastsWithDownloads) { item in
                    NavigationLink(value: navigationRoute(for: item)) {
                      DownloadedPodcastCell(
                        title: item.title,
                        imageURL: item.imageURL,
                        downloadCount: item.downloadCount
                      )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .modifier(
                      DownloadedPodcastContextMenuModifier(
                        podcast: item.podcast,
                        modelContext: modelContext,
                        onUnsubscribed: {
                          Task { await viewModel.refreshDownloadedEpisodes() }
                        }
                      )
                    )
                  }
                }
                .padding(.horizontal)
              }
            }
          }
          .padding(.vertical)
        }
      }
    }
    .navigationTitle("Downloaded")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .refreshable {
      await viewModel.refreshDownloadedEpisodes()
    }
    .onAppear {
      viewModel.setModelContext(modelContext)
    }
    .task {
      await viewModel.refreshDownloadedEpisodes()
    }
    .task {
      // Refresh when a download completes so counts update in real time.
      for await _ in NotificationCenter.default.notifications(named: .episodeDownloadCompleted) {
        await viewModel.refreshDownloadedEpisodes()
      }
    }
  }

  private func navigationRoute(for item: DownloadedPodcastGroup) -> LibrarySubpageRoute {
    .downloadedPodcast(item.title)
  }
}

private struct DownloadedPodcastContextMenuModifier: ViewModifier {
  let podcast: PodcastInfoModel?
  let modelContext: ModelContext
  let onUnsubscribed: () -> Void

  func body(content: Content) -> some View {
    if let podcast {
      content
        .podcastContextMenu(
          podcast: podcast,
          modelContext: modelContext,
          onUnsubscribed: onUnsubscribed
        )
    } else {
      content
    }
  }
}

// MARK: - Active Downloads Section Card

/// Compact card shown at the top of DownloadedPodcastsGridView when
/// downloads are in progress. Tapping navigates to ActiveDownloadsView.
struct ActiveDownloadsSectionCard: View {
  let viewModel: LibraryViewModel

  var body: some View {
    NavigationLink(value: LibrarySubpageRoute.downloadingEpisodes) {
      HStack(spacing: 12) {
        ZStack {
          Circle()
            .fill(Color.blue.opacity(0.12))
            .frame(width: 44, height: 44)
          ProgressView()
            .scaleEffect(0.7)
            .tint(.blue)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text("Downloading")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
          Text(downloadingSubtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }
    .buttonStyle(.plain)
  }

  private var downloadingSubtitle: String {
    let count = viewModel.downloadingEpisodes.count
    return count == 1 ? "1 episode" : "\(count) episodes"
  }
}

// MARK: - Active Downloads View

/// Full list of all currently downloading episodes with cancel support.
struct ActiveDownloadsView: View {
  let viewModel: LibraryViewModel
  private let downloadManager = DownloadManager.shared

  var body: some View {
    Group {
      if viewModel.downloadingEpisodes.isEmpty {
        VStack(spacing: 16) {
          Image(systemName: "arrow.down.circle")
            .font(.system(size: 50))
            .foregroundStyle(.secondary)
          Text("No Active Downloads")
            .font(.headline)
          Text("Downloads in progress will appear here")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List {
          ForEach(viewModel.downloadingEpisodes) { episode in
            ActiveDownloadRow(episode: episode, downloadManager: downloadManager)
              .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
          }
        }
        .listStyle(.plain)
      }
    }
    .navigationTitle("Downloading")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }
}

// MARK: - Active Download Row (with cancel button)

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

// MARK: - Downloaded Podcast Cell

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

// MARK: - Downloaded Episodes View (Sub-page)

struct DownloadedEpisodesView: View {
  @Bindable var viewModel: LibraryViewModel
  let showEpisodeArtwork: Bool
  var podcastTitleFilter: String? = nil
  @Environment(\.modelContext) private var modelContext
  @State private var episodeToDelete: LibraryEpisode?
  @State private var showDeleteConfirmation = false
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
                    episodeToDelete = episode
                    showDeleteConfirmation = true
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
    .confirmationDialog(
      "Delete Download",
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let episode = episodeToDelete {
          LibraryEpisodeActions.deleteDownload(episode, episodeModels: episodeModels, context: modelContext)
          refreshTask?.cancel()
          refreshTask = Task { await viewModel.refreshDownloadedEpisodes() }
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

// MARK: - Downloading Episode Row

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
