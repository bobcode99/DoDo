//
//  ShowsListView.swift
//  DoDoWatch
//
//  Subscribed shows, straight out of the CloudKit-mirrored store the phone
//  writes. Nothing is fetched to draw this screen — that is what carrying
//  `imageURL` and `latestEpisodeDate` on SubscribedPodcastModel buys.
//

import CloudKit
import SwiftData
import SwiftUI

struct ShowsListView: View {
  /// Sorted in the query rather than in Swift so SwiftData does it in SQLite.
  /// Rows written before `latestEpisodeDate` existed carry nil, which sorts
  /// last under `.reverse` — the same place they belong anyway, since nothing
  /// is known about when they last published.
  @Query(sort: \SubscribedPodcastModel.latestEpisodeDate, order: .reverse)
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
            ShowRow(podcast: podcast)
          }
        }
      }
    }
    .listStyle(.carousel)
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

/// Artwork, title, and how long ago the show last published — the last of these
/// being the reason the list is ordered the way it is. Without it the order
/// looks arbitrary.
private struct ShowRow: View {
  let podcast: SubscribedPodcastModel

  var body: some View {
    HStack(spacing: 10) {
      WatchArtwork(urlString: podcast.imageURL, size: 44)

      VStack(alignment: .leading, spacing: 2) {
        Text(podcast.title)
          .font(.body)
          .lineLimit(2)

        if let date = podcast.latestEpisodeDate {
          Text(date, format: .relative(presentation: .named))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
    }
    .padding(.vertical, 2)
  }
}
