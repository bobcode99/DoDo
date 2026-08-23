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
  private var syncCompletedObserver: NSObjectProtocol?

  /// Set while a resubscribe pass runs. CloudKit's initial import fires many
  /// remote-change notifications in quick succession, and every save inside a
  /// pass fires more — without this gate each notification spawned its own
  /// full feed-refetching pass (the same feeds downloaded dozens of times).
  private var isResubscribing = false
  private var needsResubscribeRecheck = false

  // Internal (not private) so tests can create an isolated instance against
  // an in-memory container instead of sharing app-wide singleton state.
  init() {}

  func setModelContainer(_ container: ModelContainer) {
    guard context == nil else { return }
    context = container.mainContext
    observeRemoteChanges()
    observeFeedRefreshes()
    backfillExistingSubscriptions()
    // Rows that predate `latestEpisodeDate` carry nil and would sort last
    // forever otherwise — the next feed refresh is hours away.
    refreshMirroredMetadata()
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
          rssUrl: podcast.rssUrl,
          title: podcast.title,
          imageURL: podcast.imageURL,
          latestEpisodeDate: podcast.latestEpisodeDate
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
          existing.latestEpisodeDate = podcast.latestEpisodeDate
        } else {
          context.insert(
            SubscribedPodcastModel(
              rssUrl: rssUrl,
              title: podcast.title,
              imageURL: podcast.imageURL,
              latestEpisodeDate: podcast.latestEpisodeDate
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

  /// Keeps the mirrored rows current after a feed refresh.
  ///
  /// `sync(from:)` only fires on subscribe/unsubscribe, so without this a show
  /// that published this morning would still carry last month's
  /// `latestEpisodeDate` and sort to the bottom of the watch's list. Title and
  /// artwork ride along because a feed can rename itself or change its cover.
  private func observeFeedRefreshes() {
    syncCompletedObserver = NotificationCenter.default.addObserver(
      forName: .podcastSyncCompleted, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.refreshMirroredMetadata()
      }
    }
  }

  /// One pass over the mirror, writing only rows that actually changed — a
  /// no-op save would churn CloudKit on every sync round for no benefit.
  func refreshMirroredMetadata() {
    guard let context else { return }

    let subscribed =
      (try? context.fetch(
        FetchDescriptor<PodcastInfoModel>(predicate: #Predicate { $0.isSubscribed })
      )) ?? []
    guard !subscribed.isEmpty else { return }

    let byRSS = Dictionary(
      subscribed.compactMap { $0.rssUrl.isEmpty ? nil : ($0.rssUrl, $0) },
      uniquingKeysWith: { first, _ in first }
    )

    let rows = (try? context.fetch(FetchDescriptor<SubscribedPodcastModel>())) ?? []
    var changed = 0
    for row in rows {
      guard let podcast = byRSS[row.rssUrl] else { continue }
      guard row.title != podcast.title
        || row.imageURL != podcast.imageURL
        || row.latestEpisodeDate != podcast.latestEpisodeDate
      else { continue }
      row.title = podcast.title
      row.imageURL = podcast.imageURL
      row.latestEpisodeDate = podcast.latestEpisodeDate
      changed += 1
    }
    guard changed > 0 else { return }

    do {
      try context.save()
      logger.info("Refreshed \(changed, privacy: .public) mirrored subscription(s)")
    } catch {
      logger.error("Mirror refresh failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func observeRemoteChanges() {
    remoteChangeObserver = NotificationCenter.default.addObserver(
      forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.scheduleResubscribe()
      }
    }
  }

  /// Collapses overlapping remote-change notifications: one pass runs now, and
  /// any notifications that land while it works collapse into a single repeat
  /// afterwards — rather than one full pass per notification.
  private func scheduleResubscribe() {
    if isResubscribing {
      needsResubscribeRecheck = true
      return
    }
    isResubscribing = true
    Task {
      // `defer`, not a trailing assignment: a cancelled task would otherwise
      // leave the flag set and silently drop every later resubscribe.
      defer { isResubscribing = false }
      repeat {
        needsResubscribeRecheck = false
        await resubscribeMissingPodcasts()
      } while needsResubscribeRecheck
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

    // One fetch, not two per row: this runs on the main actor every time
    // CloudKit reports a change, and a per-row descriptor meant 2N queries.
    // "Already have it" means a subscribed model matching this feed URL *or*
    // the mirrored title — matching URLs alone misses a subscribed title-twin
    // when duplicate models exist, so the row read as missing forever and
    // every pass refetched its whole feed.
    let subscribed =
      (try? context.fetch(
        FetchDescriptor<PodcastInfoModel>(predicate: #Predicate { $0.isSubscribed })
      )) ?? []
    let subscribedURLs = Set(subscribed.map(\.rssUrl))
    let subscribedTitles = Set(subscribed.map(\.title))

    for row in remoteRows {
      guard !subscribedURLs.contains(row.rssUrl),
            !subscribedTitles.contains(row.title) else { continue }
      await subscribeSilently(rssUrl: row.rssUrl, context: context)
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
        // Already subscribed → nothing to persist; saving anyway would fire
        // another remote-change notification and re-run this whole flow.
        guard !existingByTitle.isSubscribed else { return }
        existingByTitle.setSubscribed(true)
      } else {
        let model = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: .now, isSubscribed: true)
        context.insert(model)
      }
      try context.save()
      logger.info("Auto-subscribed from iCloud: \(title, privacy: .public)")
    } catch {
      logger.error("Failed to auto-subscribe \(rssUrl, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }
}
