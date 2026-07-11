//
//  DownloadedPodcastsGridView.swift
//  PodcastAnalyzer
//
//  Downloaded podcasts grid (Sub-page)
//

import SwiftData
import SwiftUI

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
