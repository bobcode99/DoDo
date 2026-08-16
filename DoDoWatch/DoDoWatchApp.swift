//
//  DoDoWatchApp.swift
//  DoDoWatch
//
//  The watch app is standalone: it reads the same CloudKit private database the
//  iPhone and Mac write to, so subscriptions, playback progress and Up Next
//  arrive without the phone being involved. WatchConnectivity is reserved for
//  the two things CloudKit is too slow for — mirroring what is playing right
//  now, and driving the phone as a remote.
//
//  An App Group would not work here: those are per-device, so the widget's
//  transport (WidgetDataManager) stops at the phone.
//

import SwiftData
import SwiftUI

@main
struct DoDoWatchApp: App {
  /// Matches the identifier in `PodcastAnalyzerApp.cloudKitContainerIdentifier`.
  /// Same container, same records — that is the whole sync design.
  static let cloudKitContainerIdentifier = "iCloud.com.jn.PodcastAnalyzer"

  let sharedModelContainer: ModelContainer = {
    let fullSchema = Schema([
      PlaybackProgressModel.self,
      SubscribedPodcastModel.self,
      QueueItemModel.self,
    ])

    // A subset of the phone's `cloudConfiguration` (PodcastAnalyzerApp.swift):
    // same container and same store name, minus `EpisodeAIAnalysis`, which the
    // watch has no screen for and which would drag the whole AI provider stack
    // into this target. CloudKit record types are per-model and additive, so
    // the phone keeps syncing analyses while the watch simply ignores them.
    let cloudConfiguration = ModelConfiguration(
      "cloud",
      schema: fullSchema,
      isStoredInMemoryOnly: false,
      cloudKitDatabase: .private(cloudKitContainerIdentifier)
    )

    do {
      return try ModelContainer(for: fullSchema, configurations: [cloudConfiguration])
    } catch {
      // Same bargain as the phone: this project ships no migrations, so a
      // schema change is allowed to discard the local copy and re-download it
      // from CloudKit rather than refuse to launch. Cheaper here than on the
      // phone — everything in this store is a CloudKit mirror, so nothing is
      // actually lost.
      let support = URL.applicationSupportDirectory
      for name in ["cloud.store", "cloud.store-wal", "cloud.store-shm"] {
        try? FileManager.default.removeItem(at: support.appending(path: name))
      }
      do {
        return try ModelContainer(for: fullSchema, configurations: [cloudConfiguration])
      } catch {
        fatalError("Could not create ModelContainer even after store reset: \(error)")
      }
    }
  }()

  var body: some Scene {
    WindowGroup {
      RootMenuView()
    }
    .modelContainer(sharedModelContainer)
  }
}
