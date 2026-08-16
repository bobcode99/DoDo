//
//  ShowsListView.swift
//  DoDoWatch
//
//  Subscribed shows, straight out of the CloudKit-mirrored store the phone
//  writes. Nothing is fetched to draw this screen — that is what carrying
//  `imageURL` on SubscribedPodcastModel buys.
//

import SwiftData
import SwiftUI

struct ShowsListView: View {
  @Query(sort: \SubscribedPodcastModel.dateSubscribed, order: .reverse)
  private var subscriptions: [SubscribedPodcastModel]

  var body: some View {
    List {
      if subscriptions.isEmpty {
        ContentUnavailableView(
          "No Shows",
          systemImage: "antenna.radiowaves.left.and.right.slash",
          description: Text("Subscribe on your iPhone and your shows appear here.")
        )
      } else {
        ForEach(subscriptions) { podcast in
          NavigationLink {
            ShowEpisodesView(rssUrl: podcast.rssUrl, title: podcast.title)
          } label: {
            HStack(spacing: 8) {
              WatchArtwork(urlString: podcast.imageURL)
              Text(podcast.title)
                .font(.body)
                .lineLimit(2)
            }
          }
        }
      }
    }
    .navigationTitle("Shows")
  }
}
