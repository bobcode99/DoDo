//
//  NotifyShowsView.swift
//  PodcastAnalyzer
//
//  Picks which subscribed shows send a new-episode notification. Writes
//  PodcastInfoModel.notifyNewEpisodes; BackgroundSyncManager reads it.
//

import SwiftData
import SwiftUI

struct NotifyShowsView: View {
  @Environment(\.modelContext) private var modelContext

  // Only denormalized fields are read, so the episode blob is never decoded.
  @Query(filter: #Predicate<PodcastInfoModel> { $0.isSubscribed }, sort: \PodcastInfoModel.title)
  private var podcasts: [PodcastInfoModel]

  var body: some View {
    List {
      if podcasts.isEmpty {
        ContentUnavailableView(
          "No Subscriptions",
          systemImage: "square.stack",
          description: Text("Shows you follow appear here.")
        )
      } else {
        Section {
          ForEach(podcasts) { podcast in
            NotifyShowRow(podcast: podcast)
          }
        } footer: {
          Text("Only shows that are on send a notification when a new episode arrives.")
        }
      }
    }
    .navigationTitle("Notify for Shows")
    .platformToolbarTitleDisplayMode()
    .toolbar {
      if !podcasts.isEmpty {
        Menu("Set All") {
          Button("Turn All On") { setAll(true) }
          Button("Turn All Off") { setAll(false) }
        }
      }
    }
  }

  private func setAll(_ on: Bool) {
    for podcast in podcasts {
      podcast.notifyNewEpisodes = on
    }
    modelContext.saveOrLog()
  }
}

private struct NotifyShowRow: View {
  @Bindable var podcast: PodcastInfoModel
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    Toggle(isOn: $podcast.notifyNewEpisodes) {
      HStack(spacing: 12) {
        CachedArtworkImage(urlString: podcast.imageURL, size: 36, cornerRadius: 6)
        Text(podcast.title)
          .lineLimit(2)
      }
    }
    .onChange(of: podcast.notifyNewEpisodes) {
      modelContext.saveOrLog()
    }
  }
}
