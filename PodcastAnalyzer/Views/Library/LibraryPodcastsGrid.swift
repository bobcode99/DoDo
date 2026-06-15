//
//  LibraryPodcastsGrid.swift
//  PodcastAnalyzer
//
//  2-column podcast grid for the Library tab.
//  Extracted from LibraryView so SwiftUI can diff it independently.
//

import SwiftData
import SwiftUI

struct LibraryPodcastsGrid: View {
  let sortedPodcasts: [PodcastGridItem]
  let podcastModelByID: [PodcastInfoModel.ID: PodcastInfoModel]
  let modelContext: ModelContext
  let onError: (String) -> Void
  let onUnsubscribed: () -> Void

  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Your Podcasts")
          .font(.headline)
        Spacer()
        Text("\(sortedPodcasts.count)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      if sortedPodcasts.isEmpty {
        emptyView
      } else {
        LazyVGrid(columns: columns, spacing: 16) {
          ForEach(sortedPodcasts) { item in
            if let model = podcastModelByID[item.id] {
              NavigationLink(value: PodcastBrowseRoute(podcastModel: model)) {
                PodcastGridCell(item: item)
              }
              .buttonStyle(.plain)
              .contentShape(Rectangle())
              .podcastContextMenu(
                podcast: model,
                modelContext: modelContext,
                onError: onError,
                onUnsubscribed: onUnsubscribed
              )
            }
          }
        }
        // Animates only the reposition when `sortedPodcasts` changes (e.g. a
        // background sync brings new episodes and a show jumps to the front).
        // The expensive rebuild already happened in applyPodcastsIfChanged, so
        // this animates cheap layout moves of stable-id cells, not the work.
        .animation(.smooth, value: sortedPodcasts)
      }
    }
  }

  private var emptyView: some View {
    VStack(spacing: 12) {
      Image(systemName: "square.stack.3d.up")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
      Text("No Subscriptions")
        .font(.headline)
      Text("Search and subscribe to podcasts to build your library")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }
}
