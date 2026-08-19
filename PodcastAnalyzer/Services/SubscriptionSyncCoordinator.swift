//
//  SubscriptionSyncCoordinator.swift
//  PodcastAnalyzer
//
//  Bridges PodcastInfoModel.isSubscribed to the CloudKit-synced
//  SubscribedPodcastModel, and applies incoming iCloud subscriptions back
//  onto the local library — so subscribing on one device brings the podcast
//  to another signed into the same Apple ID.
//

import Foundation
import SwiftData
import CoreData
import OSLog

@MainActor
final class SubscriptionSyncCoordinator {
  static let shared = SubscriptionSyncCoordinator()

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "SubscriptionSync")
  private let rssService = PodcastRssService()
  private var context: ModelContext?
  private var remoteChangeObserver: NSObjectProtocol?

  // Internal (not private) so tests can create an isolated instance against
  // an in-memory container instead of sharing app-wide singleton state.
  init() {}

  func setModelContainer(_ container: ModelContainer) {
    guard context == nil else { return }
    context = container.mainContext
    observeRemoteChanges()
    backfillExistingSubscriptions()
  }

  /// Mirrors subscriptions that predate the synced store.
  ///
  /// `sync(from:)` only runs on a state *change*, and `setSubscribed(_:)`
  /// returns early when the flag already holds the requested value — so a
  /// library subscribed before `SubscribedPodcastModel` existed never produced
  /// a row, and re-subscribing cannot produce one either. Every screen in the
  /// watch app reads that model, so without this pass the watch stays empty
  /// no matter how long CloudKit is given.
  ///
  /// Idempotent and cheap: one fetch of subscribed podcasts, one of the rows
  /// already mirrored, and a save only when something was actually missing.
  private func backfillExistingSubscriptions() {
    guard let context else { return }

    let subscribed =
      (try? context.fetch(
        FetchDescriptor<PodcastInfoModel>(predicate: #Predicate { $0.isSubscribed })
      )) ?? []
    guard !subscribed.isEmpty else { return }

    let mirrored = Set(
      ((try? context.fetch(FetchDescriptor<SubscribedPodcastModel>())) ?? []).map(\.rssUrl)
    )

    var inserted = 0
    for podcast in subscribed
    where !podcast.rssUrl.isEmpty && !mirrored.contains(podcast.rssUrl) {
      context.insert(
        SubscribedPodcastModel(
          rssUrl: podcast.rssUrl, title: podcast.title, imageURL: podcast.imageURL
        )
      )
      inserted += 1
    }
    guard inserted > 0 else { return }

    do {
      try context.save()
      logger.info("Backfilled \(inserted, privacy: .public) subscription(s) to iCloud")
    } catch {
      logger.error("Subscription backfill failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Push (local → CloudKit)

  /// Call whenever a podcast's subscribed state changes. Mirrors the
  /// subscription (or its removal) into the synced store.
  func sync(from podcast: PodcastInfoModel) {
    guard let context else {
      // Was silent, and that is how this shipped unwired: `setModelContainer`
      // was never called, so every subscribe/unsubscribe returned here and the
      // watch — which reads only the synced store — saw an empty library.
      logger.error("sync(from:) called before setModelContainer; subscription not mirrored")
      return
    }
    guard !podcast.rssUrl.isEmpty else { return }
    let rssUrl = podcast.rssUrl

    do {
      let descriptor = FetchDescriptor<SubscribedPodcastModel>(predicate: #Predicate { $0.rssUrl == rssUrl })
      let existing = try context.fetch(descriptor).first

      if podcast.isSubscribed {
        if let existing {
          existing.title = podcast.title
          existing.imageURL = podcast.imageURL
        } else {
          context.insert(
            SubscribedPodcastModel(
              rssUrl: rssUrl, title: podcast.title, imageURL: podcast.imageURL
            )
          )
        }
      } else if let existing {
        context.delete(existing)
      }
      try context.save()
    } catch {
      logger.error("Failed to sync subscription: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Detection (onboarding)

  /// True when this Apple ID already has subscriptions in iCloud — signals a
  /// returning user on a fresh install, so onboarding can skip the manual
  /// "Import Podcasts" step and restore the library instead.
  func hasCloudSubscriptions() -> Bool {
    guard let context else { return false }
    return ((try? context.fetchCount(FetchDescriptor<SubscribedPodcastModel>())) ?? 0) > 0
  }

  /// RSS URLs of every synced subscription — feed this to
  /// `PodcastImportManager.importPodcasts(from:)` for an explicit,
  /// progress-visible restore (onboarding).
  func cloudSubscriptionRSSURLs() -> [String] {
    guard let context else { return [] }
    let rows = (try? context.fetch(FetchDescriptor<SubscribedPodcastModel>())) ?? []
    return rows.map(\.rssUrl)
  }

  // MARK: - Pull (CloudKit → local, silent)

  private func observeRemoteChanges() {
    remoteChangeObserver = NotificationCenter.default.addObserver(
      forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        await self?.resubscribeMissingPodcasts()
      }
    }
  }

  /// For every synced subscription this device hasn't subscribed to yet,
  /// fetches the feed and subscribes — quietly, with no import-sheet UI,
  /// since this can fire at any time a remote change arrives (not just
  /// onboarding). Onboarding's initial restore uses
  /// `PodcastImportManager.importPodcasts(from:)` instead, which is the same
  /// underlying logic but with visible progress for that one-time flow.
  func resubscribeMissingPodcasts() async {
    guard let context else { return }
    let remoteRows = (try? context.fetch(FetchDescriptor<SubscribedPodcastModel>())) ?? []
    guard !remoteRows.isEmpty else { return }

    for row in remoteRows {
      let rssUrl = row.rssUrl
      let descriptor = FetchDescriptor<PodcastInfoModel>(predicate: #Predicate { $0.rssUrl == rssUrl })
      let local = try? context.fetch(descriptor).first
      guard local?.isSubscribed != true else { continue }
      await subscribeSilently(rssUrl: rssUrl, context: context)
    }
  }

  /// Same fetch → dedupe-by-title → create-or-mark-subscribed steps as
  /// `PodcastImportManager.processImport`, without its sheet/progress state.
  private func subscribeSilently(rssUrl: String, context: ModelContext) async {
    do {
      let podcastInfo = try await rssService.fetchPodcast(from: rssUrl)
      let title = podcastInfo.title
      let titleDescriptor = FetchDescriptor<PodcastInfoModel>(predicate: #Predicate { $0.title == title })
      if let existingByTitle = try context.fetch(titleDescriptor).first {
        existingByTitle.setSubscribed(true)
      } else {
        let model = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date(), isSubscribed: true)
        context.insert(model)
      }
      try context.save()
      logger.info("Auto-subscribed from iCloud: \(title, privacy: .public)")
    } catch {
      logger.error("Failed to auto-subscribe \(rssUrl, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }
}
