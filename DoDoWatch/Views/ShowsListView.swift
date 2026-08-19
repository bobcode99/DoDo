//
//  ShowsListView.swift
//  DoDoWatch
//
//  Subscribed shows, straight out of the CloudKit-mirrored store the phone
//  writes. Nothing is fetched to draw this screen — that is what carrying
//  `imageURL` on SubscribedPodcastModel buys.
//

import CloudKit
import SwiftData
import SwiftUI

struct ShowsListView: View {
  @Query(sort: \SubscribedPodcastModel.dateSubscribed, order: .reverse)
  private var subscriptions: [SubscribedPodcastModel]

  @State private var accountIssue: String?

  var body: some View {
    List {
      if subscriptions.isEmpty {
        ContentUnavailableView(
          "No Shows",
          systemImage: "antenna.radiowaves.left.and.right.slash",
          description: Text(
            accountIssue ?? String(localized: "Subscribe on your iPhone and your shows appear here.")
          )
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
    .task { accountIssue = await iCloudIssue() }
  }

  /// Separates "nothing subscribed yet" from "this watch cannot reach iCloud",
  /// which otherwise render as the same empty list — and only one of them is
  /// something the user can act on. Every screen here is fed by CloudKit, so a
  /// signed-out watch looks exactly like a brand-new one.
  private func iCloudIssue() async -> String? {
    let container = CKContainer(identifier: DoDoWatchApp.cloudKitContainerIdentifier)
    guard let status = try? await container.accountStatus() else { return nil }
    switch status {
    case .available:
      return nil
    case .noAccount:
      return String(localized: "Sign in to iCloud on your iPhone to see your shows here.")
    case .restricted:
      return String(localized: "iCloud is restricted on this device, so shows can't sync.")
    case .couldNotDetermine, .temporarilyUnavailable:
      return String(localized: "Can't reach iCloud right now. Shows appear once it's back.")
    @unknown default:
      return nil
    }
  }
}
