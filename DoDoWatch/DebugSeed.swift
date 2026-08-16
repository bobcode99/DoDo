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

    context.insert(
      SubscribedPodcastModel(
        rssUrl: "https://atp.fm/rss",
        title: "Accidental Tech Podcast",
        imageURL: "https://cdn.atp.fm/artwork"
      )
    )
    try? context.save()
  }
}

#endif
