//
//  MacLibraryPodcastsView.swift
//  PodcastAnalyzer
//
//  macOS Library — Podcasts grid
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacLibraryPodcastsView: View {
  @State private var viewModel = LibraryViewModel(modelContext: nil)
  @Environment(\.modelContext) private var modelContext

  @Query(
    filter: #Predicate<PodcastInfoModel> { $0.isSubscribed },
    sort: \.lastUpdated,
    order: .reverse
  ) private var subscribedPodcasts: [PodcastInfoModel]

  private let columns = [
    GridItem(.adaptive(minimum: 150, maximum: 180), spacing: 16)
  ]

  var body: some View {
    ScrollView {
      if viewModel.podcastsSortedByRecentUpdate.isEmpty {
        ContentUnavailableView(
          "No Subscriptions",
          systemImage: "square.stack.3d.up",
          description: Text("Search and subscribe to podcasts to build your library")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        LazyVGrid(columns: columns, spacing: 20) {
          ForEach(viewModel.podcastsSortedByRecentUpdate) { podcast in
            NavigationLink(value: PodcastBrowseRoute(podcastModel: podcast)) {
              MacPodcastGridCell(podcast: podcast)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(24)
      }
    }
    .navigationTitle("Your Podcasts")
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(action: {
          Task { await viewModel.refreshAllPodcasts() }
        }) {
          Image(systemName: "arrow.clockwise")
        }
        .disabled(viewModel.isLoading)
      }
    }
    .onAppear {
      viewModel.setModelContext(modelContext)
      viewModel.setPodcasts(subscribedPodcasts)
    }
    .onDisappear {
      viewModel.cleanup()
    }
    .onChange(of: subscribedPodcasts) { _, newPodcasts in
      viewModel.setPodcasts(newPodcasts)
    }
  }
}

// MARK: - Podcast Grid Cell

struct MacPodcastGridCell: View {
  let podcast: PodcastInfoModel

  /// Most recent episode pubDate, formatted as "2 days ago" etc.
  /// Mirrors the iOS PodcastGridCell so Mac users see the same
  /// "freshness" cue as on iPhone.
  private var latestEpisodeDateString: String? {
    guard let date = podcast.podcastInfo.episodes
      .lazy
      .compactMap(\.pubDate)
      .max() else { return nil }
    return Formatters.formatRelativeDate(date)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CachedArtworkImage(urlString: podcast.podcastInfo.imageURL, size: 150, cornerRadius: 10)

      Text(podcast.podcastInfo.title)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2)

      if let dateStr = latestEpisodeDateString {
        Text(dateStr)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 150)
  }
}
#endif
