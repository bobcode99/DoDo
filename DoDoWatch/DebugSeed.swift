//
//  DebugSeed.swift
//  DoDoWatch
//
//  Puts one subscription in the store so the watch has something to draw.
//
//  Exists because the watch simulator cannot reliably hold an iCloud sign-in,
//  and without one nothing arrives from CloudKit — which is where every screen
//  in this app gets its data. Debug builds only, and only when explicitly
//  asked for:
//
//      xcrun simctl launch <udid> com.jn.PodcastAnalyzer.watchkitapp -seedWatchDemoData
//

#if DEBUG

import Foundation
import SwiftData

enum DebugSeed {
  private static let launchArgument = "-seedWatchDemoData"

  static var isRequested: Bool {
    CommandLine.arguments.contains(launchArgument)
  }

  /// Inserts a single well-known public feed, and only into an empty store —
  /// so it can never overwrite records that arrived from CloudKit.
  @MainActor
  static func apply(to context: ModelContext) {
    guard isRequested else { return }
    let existing = (try? context.fetchCount(FetchDescriptor<SubscribedPodcastModel>())) ?? 0
    guard existing == 0 else { return }

    // Two rows with different `latestEpisodeDate`s, so the Shows list's
    // recency ordering and its relative-date subtitle are both visible without
    // an iCloud sign-in.
    let seeds: [(rss: String, title: String, image: String, daysAgo: Int)] = [
      ("https://atp.fm/rss", "Accidental Tech Podcast", "https://cdn.atp.fm/artwork", 2),
      ("https://feeds.simplecast.com/xKJ93w_9", "The Talk Show", "", 11),
    ]
    for seed in seeds {
      context.insert(
        SubscribedPodcastModel(
          rssUrl: seed.rss,
          title: seed.title,
          imageURL: seed.image,
          latestEpisodeDate: Calendar.current.date(
            byAdding: .day, value: -seed.daysAgo, to: .now)
        )
      )
    }
    try? context.save()
  }
}

#endif
