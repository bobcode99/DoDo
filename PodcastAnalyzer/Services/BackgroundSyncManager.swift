//
//  BackgroundSyncManager.swift
//  PodcastAnalyzer
//
//  Manages background sync for podcast episodes with notifications
//

#if os(iOS)
import BackgroundTasks
#endif
import Foundation
import Observation
import SwiftData
import UserNotifications
import OSLog

// MARK: - Sync Notifications

extension Notification.Name {
  /// Posted when background sync completes with new episodes
  /// userInfo contains: "newEpisodeCount" (Int), "updatedPodcastTitles" ([String])
  static let podcastSyncCompleted = Notification.Name("podcastSyncCompleted")

  /// Posted when a podcast is updated (from any source)
  static let podcastDataChanged = Notification.Name("podcastDataChanged")

  /// Posted when an episode's completion state changes (played/unplayed)
  static let episodeCompletionChanged = Notification.Name("episodeCompletionChanged")
}

@MainActor
@Observable
class BackgroundSyncManager {
  static let shared = BackgroundSyncManager()

  // Background task identifier
  static let backgroundTaskIdentifier = "com.podcast.analyzer.refresh"

  // Settings
  var isBackgroundSyncEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isBackgroundSyncEnabled, forKey: Keys.backgroundSyncEnabled)
      if isBackgroundSyncEnabled {
        scheduleBackgroundRefresh()
      } else {
        cancelBackgroundRefresh()
      }
    }
  }

  var isNotificationsEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isNotificationsEnabled, forKey: Keys.notificationsEnabled)
      if isNotificationsEnabled {
        requestNotificationPermission()
      }
    }
  }

  var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
  var lastSyncDate: Date?
  var isSyncing: Bool = false
  // Progress during an active sync (both are 0 when not syncing)
  var syncProgressCurrent: Int = 0
  var syncProgressTotal: Int = 0
  // Non-nil when the last sync finished with an error
  var lastSyncError: String?

  // Minimum elapsed time before firing an immediate sync on app-foreground (30 min)
  private let minimumSyncInterval: TimeInterval = 30 * 60

  @ObservationIgnored
  private let rssService = PodcastRssService()

  @ObservationIgnored
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "BackgroundSync")

  @ObservationIgnored
  private var modelContainer: ModelContainer?

  private enum Keys {
    static let backgroundSyncEnabled = "backgroundSyncEnabled"
    static let notificationsEnabled = "notificationsEnabled"
    static let lastSyncDate = "lastSyncDate"
  }

  // No deinit — singleton lives for app lifetime.

  private init() {
    // Check if user has explicitly set the preference
    let isFirstLaunch = UserDefaults.standard.object(forKey: Keys.backgroundSyncEnabled) == nil
    if isFirstLaunch {
      self.isBackgroundSyncEnabled = true
      UserDefaults.standard.set(true, forKey: Keys.backgroundSyncEnabled)
      self.isNotificationsEnabled = true
      UserDefaults.standard.set(true, forKey: Keys.notificationsEnabled)
    } else {
      self.isBackgroundSyncEnabled = UserDefaults.standard.bool(forKey: Keys.backgroundSyncEnabled)
      self.isNotificationsEnabled = UserDefaults.standard.bool(forKey: Keys.notificationsEnabled)
    }
    if let date = UserDefaults.standard.object(forKey: Keys.lastSyncDate) as? Date {
      self.lastSyncDate = date
    }

    Task {
      await checkNotificationPermission()

      // Schedule background refresh if enabled (especially important on first launch)
      if isBackgroundSyncEnabled {
        scheduleBackgroundRefresh()
      }
    }
  }

  // MARK: - Setup

  func setModelContainer(_ container: ModelContainer) {
    self.modelContainer = container
  }

  // MARK: - Background Task Registration

  #if os(iOS)
  /// Call this in app's init to register background task (iOS only)
  static func registerBackgroundTask() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: backgroundTaskIdentifier,
      using: nil
    ) { task in
      Task { @MainActor in
        await BackgroundSyncManager.shared.handleBackgroundRefresh(task: task as! BGAppRefreshTask)
      }
    }
  }

  func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
    // Schedule for 4 hours from now (iOS may delay based on system conditions)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)

    do {
      try BGTaskScheduler.shared.submit(request)
      logger.info("Background refresh scheduled for 4 hours from now")
    } catch {
      logger.error("Failed to schedule background refresh: \(error.localizedDescription)")
    }
  }

  func cancelBackgroundRefresh() {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.backgroundTaskIdentifier)
    logger.info("Background refresh cancelled")
  }

  private func handleBackgroundRefresh(task: BGAppRefreshTask) async {
    scheduleBackgroundRefresh()

    // Wrap sync in a child Task so the expiration handler can cooperatively cancel it.
    // setTaskCompleted is called exactly once after syncTask resolves.
    let syncTask = Task { await self.performSync() }

    task.expirationHandler = { [weak self] in
      self?.logger.warning("Background refresh expired — cancelling sync")
      syncTask.cancel()
    }

    let success = await syncTask.value
    task.setTaskCompleted(success: success && !syncTask.isCancelled)
  }

  #else
  /// macOS: No-op for background task registration (use foreground timer instead)
  static func registerBackgroundTask() {
    // macOS doesn't support BGTaskScheduler
    // Use startForegroundSync() instead when app is running
  }

  func scheduleBackgroundRefresh() {
    // On macOS, use the foreground timer since apps typically stay running
    startForegroundSync()
    logger.info("macOS: Using foreground sync timer instead of background task")
  }

  func cancelBackgroundRefresh() {
    stopForegroundSync()
    logger.info("macOS: Foreground sync stopped")
  }
  #endif

  // MARK: - Manual Sync (for foreground use)

  func syncNow() async {
    guard !isSyncing else { return }
    _ = await performSync()
  }

  // MARK: - Core Sync Logic

  private func performSync() async -> Bool {
    guard let container = modelContainer else {
      logger.warning("ModelContainer not set, cannot sync")
      return false
    }

    isSyncing = true
    lastSyncError = nil
    syncProgressCurrent = 0
    syncProgressTotal = 0
    defer {
      isSyncing = false
      syncProgressCurrent = 0
      syncProgressTotal = 0
    }

    logger.info("Starting podcast sync...")

    let context = ModelContext(container)
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.isSubscribed == true }
    )

    do {
      let podcasts = try context.fetch(descriptor)
      logger.info("Found \(podcasts.count) subscribed podcasts to sync")

      syncProgressTotal = podcasts.count

      // Pre-fetch episode keys that have user data so we can preserve orphaned episodes
      // (episodes that aged off the RSS feed but were downloaded / starred / played).
      let allEpisodeModels = (try? context.fetch(FetchDescriptor<EpisodeDownloadModel>())) ?? []
      let episodesWithUserData: Set<String> = Set(
        allEpisodeModels
          .filter { $0.localAudioPath != nil || $0.isStarred || $0.isCompleted
                    || $0.lastPlaybackPosition > 0 || $0.playCount > 0 }
          .map { $0.id }
      )

      var totalNewEpisodes = 0
      var newEpisodeDetails: [(podcastTitle: String, episodeTitle: String, audioURL: String?, imageURL: String?, language: String)] = []

      // Sync all podcasts in parallel (up to 6 at a time) for faster refresh
      let maxConcurrent = 6
      await withTaskGroup(of: (Int, PodcastInfo?, String?, Error?).self) { group in
        for (index, podcast) in podcasts.enumerated() {
          // Stop enqueuing new work if the task was cancelled (e.g. BGTask expiration)
          guard !Task.isCancelled else {
            group.cancelAll()
            return
          }

          // Once we've launched maxConcurrent tasks, wait for one to finish before adding more
          if index >= maxConcurrent {
            if let result = await group.next() {
              processSyncResult(
                result, podcasts: podcasts,
                episodesWithUserData: episodesWithUserData,
                totalNewEpisodes: &totalNewEpisodes,
                newEpisodeDetails: &newEpisodeDetails
              )
              syncProgressCurrent += 1
            }
          }

          let rssUrl = podcast.podcastInfo.rssUrl
          let cachedHeader = podcast.httpCacheHeader

          // Adaptive refresh: skip if we predict the feed won't update for at least 2 hours
          if let predicted = podcast.predictedNextReleaseDate,
             predicted.timeIntervalSinceNow > 2 * 3600 {
            logger.info("Skipping \(podcast.podcastInfo.title) — next episode predicted at \(predicted)")
            syncProgressCurrent += 1
            continue
          }

          group.addTask {
            do {
              let result = try await self.rssService.fetchPodcastConditional(
                from: rssUrl, cacheHeader: cachedHeader)
              switch result {
              case .notModified:
                return (index, nil, nil, nil)  // no new data, no error
              case .updated(let podcast, let cacheHeader):
                return (index, podcast, cacheHeader, nil)
              }
            } catch {
              return (index, nil, nil, error)
            }
          }
        }

        // Collect remaining results
        for await result in group {
          processSyncResult(
            result, podcasts: podcasts,
            episodesWithUserData: episodesWithUserData,
            totalNewEpisodes: &totalNewEpisodes,
            newEpisodeDetails: &newEpisodeDetails
          )
          syncProgressCurrent += 1
        }
      }

      // Bail out cleanly if the background task was expired mid-sync
      guard !Task.isCancelled else {
        logger.info("Sync cancelled mid-flight (background time expired)")
        return false
      }

      // Save changes
      try context.save()

      // Update last sync date
      lastSyncDate = Date()
      UserDefaults.standard.set(lastSyncDate, forKey: Keys.lastSyncDate)

      // Delegate auto-download decisions to the serialized coordinator.
      if totalNewEpisodes > 0 {
        let autoDownloadCandidates = newEpisodeDetails.map { detail in
          (podcastTitle: detail.podcastTitle,
           episodeTitle: detail.episodeTitle,
           audioURL: detail.audioURL ?? "",
           language: detail.language)
        }
        await AutoDownloadCoordinator.shared.updatePendingEpisodes(autoDownloadCandidates)
        await AutoDownloadCoordinator.shared.run(reason: .feedRefresh)
      }

      // Send push notification if there are new episodes and enabled
      if totalNewEpisodes > 0 && isNotificationsEnabled && notificationPermissionStatus == .authorized {
        await sendNewEpisodesNotification(
          totalCount: totalNewEpisodes,
          details: newEpisodeDetails
        )
      }

      // Always post internal notification for UI updates (even if no new episodes, to update timestamps)
      let updatedTitles = Set(newEpisodeDetails.map { $0.podcastTitle })
      NotificationCenter.default.post(
        name: .podcastSyncCompleted,
        object: nil,
        userInfo: [
          "newEpisodeCount": totalNewEpisodes,
          "updatedPodcastTitles": Array(updatedTitles)
        ]
      )

      logger.info("Sync completed. Found \(totalNewEpisodes) new episodes total.")
      return true

    } catch {
      lastSyncError = error.localizedDescription
      logger.error("Sync failed: \(error.localizedDescription)")
      return false
    }
  }

  /// Process a single parallel sync result and merge into accumulated state
  private func processSyncResult(
    _ result: (index: Int, podcast: PodcastInfo?, cacheHeader: String?, error: Error?),
    podcasts: [PodcastInfoModel],
    episodesWithUserData: Set<String>,
    totalNewEpisodes: inout Int,
    newEpisodeDetails: inout [(podcastTitle: String, episodeTitle: String, audioURL: String?, imageURL: String?, language: String)]
  ) {
    let podcast = podcasts[result.index]

    if let error = result.error {
      logger.error("Failed to sync \(podcast.podcastInfo.title): \(error.localizedDescription)")
      return
    }

    // Save any new ETag/Last-Modified even if no new episodes
    if let newHeader = result.cacheHeader {
      podcast.httpCacheHeader = newHeader
    }

    guard let updatedPodcast = result.podcast else {
      // nil podcast with no error = HTTP 304 Not Modified — feed unchanged
      return
    }

    // Prefer GUID for dedup (most reliable), fall back to audioURL, then title
    let existingKeys = Set(podcast.podcastInfo.episodes.map { ep in
      ep.guid ?? ep.audioURL ?? ep.title
    })
    let newEpisodes = updatedPodcast.episodes.filter { ep in
      !existingKeys.contains(ep.guid ?? ep.audioURL ?? ep.title)
    }

    if !newEpisodes.isEmpty {
      totalNewEpisodes += newEpisodes.count
      for episode in newEpisodes.prefix(3) {
        newEpisodeDetails.append((
          podcastTitle: updatedPodcast.title,
          episodeTitle: episode.title,
          audioURL: episode.audioURL,
          imageURL: episode.imageURL ?? updatedPodcast.imageURL,
          language: updatedPodcast.language
        ))
      }

      // Merge: RSS episodes + orphaned episodes the user has touched (downloaded/starred/played)
      // so they don't vanish when a feed trims its backlog.
      let merged = podcast.podcastInfo.merging(updatedFrom: updatedPodcast, preservedKeys: episodesWithUserData)
      podcast.podcastInfo = merged
      podcast.lastUpdated = Date()

      // Update release schedule prediction from the latest episode pub dates
      let pubDates = updatedPodcast.episodes.compactMap { $0.pubDate }
      let (cadence, nextDate) = ReleaseScheduleGuesser.guess(pubDates: pubDates)
      podcast.detectedCadence = cadence.rawValue
      podcast.predictedNextReleaseDate = nextDate

      logger.info("Found \(newEpisodes.count) new episodes for \(updatedPodcast.title)")

      // Auto-enqueue transcription for shows the user opted into.
      // We only fire here when the engine is YAP, since YAP can transcribe
      // from a remote URL — no local audio file is needed. Local engines
      // (Whisper / AppleSpeech) require the downloaded file, so they are
      // handled by DownloadManager once the audio lands on disk.
      if podcast.autoTranscribeNewEpisodes,
         let engine = TranscriptManager.shared.engineForAutoEnqueue(podcastTitle: updatedPodcast.title),
         engine == .yapServer {
        for episode in newEpisodes {
          guard !TranscriptManager.shared.isGenerating(
            episodeTitle: episode.title, podcastTitle: updatedPodcast.title
          ) else { continue }
          TranscriptManager.shared.queueTranscript(
            episodeTitle: episode.title,
            podcastTitle: updatedPodcast.title,
            audioPath: "",
            audioRemoteURL: episode.audioURL,
            language: updatedPodcast.language,
            engine: .yapServer
          )
        }
        logger.info("Auto-enqueued \(newEpisodes.count) YAP transcript jobs for \(updatedPodcast.title)")
      }
    }
  }

  // MARK: - Notifications

  func requestNotificationPermission() {
    Task {
      do {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(
          options: [.alert, .sound, .badge]
        )
        if granted {
          notificationPermissionStatus = .authorized
          logger.info("Notification permission granted")
        } else {
          notificationPermissionStatus = .denied
          isNotificationsEnabled = false
          logger.info("Notification permission denied")
        }
      } catch {
        logger.error("Failed to request notification permission: \(error.localizedDescription)")
      }
    }
  }

  func checkNotificationPermission() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    notificationPermissionStatus = settings.authorizationStatus
  }

  private func sendNewEpisodesNotification(
    totalCount: Int,
    details: [(podcastTitle: String, episodeTitle: String, audioURL: String?, imageURL: String?, language: String)]
  ) async {
    let content = UNMutableNotificationContent()

    if totalCount == 1, let first = details.first {
      content.title = "New Episode"
      content.body = "\(first.podcastTitle): \(first.episodeTitle)"
      // Include episode info for navigation on tap
      content.userInfo = [
        "type": "newEpisode",
        "podcastTitle": first.podcastTitle,
        "episodeTitle": first.episodeTitle,
        "audioURL": first.audioURL ?? "",
        "imageURL": first.imageURL ?? "",
        "language": first.language
      ]
    } else if details.count <= 3 {
      content.title = "\(totalCount) New Episodes"
      content.body = details.map { $0.podcastTitle }.joined(separator: ", ")
      content.userInfo = ["type": "multipleEpisodes"]
    } else {
      content.title = "\(totalCount) New Episodes"
      let podcastNames = Set(details.map { $0.podcastTitle })
      content.body = "From \(podcastNames.count) podcasts"
      content.userInfo = ["type": "multipleEpisodes"]
    }

    content.sound = .default
    content.badge = NSNumber(value: totalCount)

    let request = UNNotificationRequest(
      identifier: UUID().uuidString,
      content: content,
      trigger: nil  // Deliver immediately
    )

    do {
      try await UNUserNotificationCenter.current().add(request)
      logger.info("Notification sent for \(totalCount) new episodes")
    } catch {
      logger.error("Failed to send notification: \(error.localizedDescription)")
    }
  }

  // MARK: - Foreground Timer (Optional: for when app is active)

  @ObservationIgnored
  private var foregroundSyncTask: Task<Void, Never>?

  func startForegroundSync() {
    guard isBackgroundSyncEnabled else { return }

    stopForegroundSync()
    foregroundSyncTask = Task { [weak self] in
      guard let self else { return }

      // Only sync immediately if data is stale (avoids redundant fetch every app-foreground)
      if let last = lastSyncDate {
        let age = Date().timeIntervalSince(last)
        if age >= minimumSyncInterval {
          logger.info("Foreground sync: lastSync \(Int(age))s ago (>= \(Int(self.minimumSyncInterval))s threshold) — syncing now")
          await self.syncNow()
        } else {
          logger.info("Foreground sync: lastSync \(Int(age))s ago — fresh, skipping immediate sync")
        }
      } else {
        logger.info("Foreground sync: no prior sync recorded — syncing now")
        await self.syncNow()
      }

      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(4 * 60 * 60))
        if Task.isCancelled { return }
        await self.syncNow()
      }
    }
    logger.info("Foreground sync timer started (4-hour interval, immediate only if stale)")
  }

  func stopForegroundSync() {
    foregroundSyncTask?.cancel()
    foregroundSyncTask = nil
  }
}
