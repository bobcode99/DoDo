//
//  RootMenuView.swift
//  DoDoWatch
//
//  Root of the watch app. For now it exists to prove the CloudKit container
//  reaches the watch — the show count below comes from records the iPhone
//  wrote. The menu rows arrive as their screens land.
//

import SwiftData
import SwiftUI

struct RootMenuView: View {
  @Query(sort: \SubscribedPodcastModel.dateSubscribed, order: .reverse)
  private var subscriptions: [SubscribedPodcastModel]

  var body: some View {
    NavigationStack {
      List {
        Section("Shows") {
          if subscriptions.isEmpty {
            Text("No shows yet")
              .foregroundStyle(.secondary)
          } else {
            ForEach(subscriptions) { podcast in
              Text(podcast.title)
                .lineLimit(2)
            }
          }
        }
      }
      .navigationTitle("DoDo")
    }
  }
}
