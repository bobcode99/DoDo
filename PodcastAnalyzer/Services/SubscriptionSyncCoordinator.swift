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
  }

  // MARK: - Push (local → CloudKit)

  /// Call whenever a podcast's subscribed state changes. Mirrors the
  /// subscription (or its removal) into the synced store.
  func sync(from podcast: PodcastInfoModel) {
    guard let context, !podcast.rssUrl.isEmpty else { return }
    let rssUrl = podcast.rssUrl

    do {
      let descriptor = FetchDescriptor<SubscribedPodcastModel>(predicate: #Predicate { $0.rssUrl == rssUrl })
      let existing = try context.fetch(descriptor).first

      if podcast.isSubscribed {
        if let existing {
          existing.title = podcast.title
        } else {
          context.insert(SubscribedPodcastModel(rssUrl: rssUrl, title: podcast.title))
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
        existingByTitle.isSubscribed = true
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
