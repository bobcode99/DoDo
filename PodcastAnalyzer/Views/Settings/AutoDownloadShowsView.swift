//
//  AutoDownloadShowsView.swift
//  PodcastAnalyzer
//
//  Every subscribed show's auto-download setting on one screen, instead of
//  opening each show's ••• menu. Same three-state field the menu writes.
//

import SwiftData
import SwiftUI

struct AutoDownloadShowsView: View {
  @Environment(\.modelContext) private var modelContext

  // Only denormalized fields (title, imageURL, autoDownloadSetting) are read,
  // so the podcastInfo episode blob is never decoded.
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
            AutoDownloadShowRow(podcast: podcast)
          }
        } footer: {
          Text("Use Global Setting follows Download New Episodes.")
        }
      }
    }
    .navigationTitle("Auto Download")
    .platformToolbarTitleDisplayMode()
    .toolbar {
      if !podcasts.isEmpty {
        Menu("Set All") {
          ForEach(AutoDownloadSetting.allCases, id: \.rawValue) { setting in
            Button(setting.displayName) { setAll(setting) }
          }
        }
      }
    }
  }

  private func setAll(_ setting: AutoDownloadSetting) {
    for podcast in podcasts {
      podcast.autoDownloadSetting = setting.rawValue
    }
    modelContext.saveOrLog()
  }
}

private struct AutoDownloadShowRow: View {
  @Bindable var podcast: PodcastInfoModel
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    Picker(selection: $podcast.autoDownloadSetting) {
      ForEach(AutoDownloadSetting.allCases, id: \.rawValue) { setting in
        Text(setting.displayName).tag(setting.rawValue)
      }
    } label: {
      HStack(spacing: 12) {
        CachedArtworkImage(urlString: podcast.imageURL, size: 36, cornerRadius: 6)
        Text(podcast.title)
          .lineLimit(2)
      }
    }
    #if os(iOS)
    .pickerStyle(.menu)
    #endif
    .onChange(of: podcast.autoDownloadSetting) {
      modelContext.saveOrLog()
    }
  }
}
