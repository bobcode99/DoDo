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
import UniformTypeIdentifiers
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
    #if targetEnvironment(simulator)
    // The Simulator has no background-task daemon, so every submission is
    // rejected — the system (not us) logs "Error updating background task
    // request … BGSystemTaskSchedulerErrorDomain Code=3" and nothing is ever
    // scheduled. Exercise `handleBackgroundRefresh` with the debugger instead:
    //   e -l objc -- (void)[[BGTaskScheduler sharedScheduler]
    //     _simulateLaunchForTaskWithIdentifier:@"com.podcast.analyzer.refresh"]
    logger.debug("Simulator — skipping background refresh submission (unsupported)")
    #else
    Task { [weak self] in
      guard let self else { return }
      // Only one BGAppRefreshTaskRequest can be pending, and submitting again
      // silently *replaces* it — pushing earliestBeginDate another 4h out.
      // This is called on every launch and every foreground→background
      // transition, so an app opened more often than every 4 hours would keep
      // resetting its own timer and never become eligible to run.
      let pending = await BGTaskScheduler.shared.pendingTaskRequests()
      guard !pending.contains(where: { $0.identifier == Self.backgroundTaskIdentifier }) else {
        self.logger.debug("Background refresh already pending — leaving its schedule intact")
        return
      }
      self.submitBackgroundRefresh()
    }
    #endif
  }

  private func submitBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
    // Schedule for 4 hours from now (iOS may delay based on system conditions)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)

    do {
      try BGTaskScheduler.shared.submit(request)
      logger.info("Background refresh scheduled for 4 hours from now")
    } catch {
      // `localizedDescription` on a BGTaskScheduler error is just "The
      // operation couldn't be completed", which hides which cause fired.
      // Domain + code identifies it: 1 = unavailable (the user turned off
      // Background App Refresh), 2 = too many pending, 3 = not permitted.
      let nsError = error as NSError
      logger.error(
        "Failed to schedule background refresh: \(nsError.domain, privacy: .public) code \(nsError.code)")
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
      var newEpisodeDetails: [(podcastTitle: String, episodeTitle: String, audioURL: String?, imageURL: String?, language: String, summary: String?)] = []

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

        await enqueueAutoAddEpisodes(newEpisodeDetails, podcasts: podcasts)
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
      logger.error("Sync failed: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  /// Process a single parallel sync result and merge into accumulated state
  private func processSyncResult(
    _ result: (index: Int, podcast: PodcastInfo?, cacheHeader: String?, error: Error?),
    podcasts: [PodcastInfoModel],
    episodesWithUserData: Set<String>,
    totalNewEpisodes: inout Int,
    newEpisodeDetails: inout [(podcastTitle: String, episodeTitle: String, audioURL: String?, imageURL: String?, language: String, summary: String?)]
  ) {
    let podcast = podcasts[result.index]

    if let error = result.error {
      logger.error("Failed to sync \(podcast.podcastInfo.title): \(error.localizedDescription, privacy: .public)")
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

    // The conditional GET returned 200, so the feed content changed — apply the
    // merge even when no *new* episode appeared. Gating this on newEpisodes
    // used to drop metadata updates (descriptions, fixed audio URLs, artwork,
    // edited episodes) and left the release prediction stale.
    // Merge: RSS episodes + orphaned episodes the user has touched
    // (downloaded/starred/played) so they don't vanish when a feed trims its backlog.
    let merged = podcast.podcastInfo.merging(updatedFrom: updatedPodcast, preservedKeys: episodesWithUserData)
    podcast.applyPodcastInfo(merged)
    podcast.lastUpdated = Date()

    // Update release schedule prediction from the latest episode pub dates
    let pubDates = updatedPodcast.episodes.compactMap { $0.pubDate }
    let (cadence, nextDate) = ReleaseScheduleGuesser.guess(pubDates: pubDates)
    podcast.detectedCadence = cadence.rawValue
    podcast.predictedNextReleaseDate = nextDate

    if !newEpisodes.isEmpty {
      totalNewEpisodes += newEpisodes.count
      for episode in newEpisodes.prefix(3) {
        newEpisodeDetails.append((
          podcastTitle: updatedPodcast.title,
          episodeTitle: episode.title,
          audioURL: episode.audioURL,
          imageURL: episode.imageURL ?? updatedPodcast.imageURL,
          language: updatedPodcast.language,
          summary: episode.podcastEpisodeDescription
        ))
      }

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
          TranscriptManager.shared.queueAutoTranscript(
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
        logger.error("Failed to request notification permission: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  func checkNotificationPermission() async {
    let settings = await UNUserNotificationCenter.current().notificationSettings()
    notificationPermissionStatus = settings.authorizationStatus
  }

  /// Add newly-found episodes to the play queue for shows configured to do so.
  ///
  /// Pocket Casts stages these in a table because its refresh and its
  /// post-refresh processing are separate operations; ours is one function, so
  /// the candidates are still in hand and no staging is needed.
  @MainActor
  private func enqueueAutoAddEpisodes(
    _ details: [(podcastTitle: String, episodeTitle: String, audioURL: String?, imageURL: String?, language: String, summary: String?)],
    podcasts: [PodcastInfoModel]
  ) async {
    var settings: [String: AutoAddToQueueSetting] = [:]
    for podcast in podcasts {
      guard let setting = AutoAddToQueueSetting(rawValue: podcast.autoAddToQueueSetting),
        setting != .off
      else { continue }
      settings[podcast.title] = setting
    }
    guard !settings.isEmpty else { return }

    let audioManager = EnhancedAudioManager.shared
    // Oldest first, so a show set to "top" ends up with its newest episode
    // nearest the front rather than buried under the rest of the batch.
    for detail in details.reversed() {
      guard let setting = settings[detail.podcastTitle],
        let audioURL = detail.audioURL, !audioURL.isEmpty
      else { continue }

      // Stop quietly at the cap rather than going through the adding path,
      // which alerts the user — correct for a menu tap, wrong for a sync.
      guard audioManager.queueHasRoom else {
        logger.info("Auto-add stopped: queue is full")
        return
      }

      let id = "\(detail.podcastTitle)\u{1F}\(detail.episodeTitle)"
      guard !audioManager.queue.contains(where: { $0.id == id }),
        audioManager.currentEpisode?.id != id
      else { continue }

      let episode = PlaybackEpisode(
        id: id,
        title: detail.episodeTitle,
        podcastTitle: detail.podcastTitle,
        audioURL: audioURL,
        imageURL: detail.imageURL
      )

      // Stop-adding at the cap, which is Pocket Casts' `.stopAdding` policy.
      // Their ring-buffer alternative can wait until someone asks for it.
      if setting == .top {
        audioManager.playNext(episode)
      } else {
        audioManager.addToQueue(episode)
      }
      logger.info("Auto-added to queue (\(setting.rawValue)): \(detail.episodeTitle, privacy: .public)")
    }
  }

  private func sendNewEpisodesNotification(
    totalCount: Int,
    details: [(podcastTitle: String, episodeTitle: String, audioURL: String?, imageURL: String?, language: String, summary: String?)]
  ) async {
    let center = UNUserNotificationCenter.current()

    // One notification per episode — each is individually tappable and iOS
    // stacks them per show via threadIdentifier. `details` is already capped
    // at 3 episodes per podcast by processSyncResult, so a big backlog can't
    // spam the lock screen.
    for detail in details {
      // Record in the in-app inbox first; it drives the app icon badge.
      NotificationInbox.shared.add(
        podcastTitle: detail.podcastTitle,
        episodeTitle: detail.episodeTitle,
        audioURL: detail.audioURL ?? "",
        imageURL: detail.imageURL ?? ""
      )

      let content = UNMutableNotificationContent()
      // Podcast as the bold title, episode as the body — mirrors Apple Podcasts.
      content.title = detail.podcastTitle
      content.subtitle = "New Episode"
      // Episode title first, summary after: the collapsed banner truncates to
      // the title, the long-press expansion shows the whole thing. Cheaper than
      // a notification content extension for the same result.
      if let summary = Self.plainSummary(detail.summary) {
        content.body = "\(detail.episodeTitle)\n\n\(summary)"
      } else {
        content.body = detail.episodeTitle
      }
      content.threadIdentifier = detail.podcastTitle  // stack by show
      content.categoryIdentifier = NewEpisodeNotification.categoryIdentifier
      content.userInfo = [
        "type": "newEpisode",
        "podcastTitle": detail.podcastTitle,
        "episodeTitle": detail.episodeTitle,
        "audioURL": detail.audioURL ?? "",
        "imageURL": detail.imageURL ?? "",
        "language": detail.language
      ]
      // Best-effort artwork thumbnail; skipped on failure.
      if let attachment = await imageAttachment(from: detail.imageURL) {
        content.attachments = [attachment]
      }
      content.sound = .default
      content.badge = NSNumber(value: NotificationInbox.shared.unreadCount)

      do {
        try await center.add(UNNotificationRequest(
          identifier: UUID().uuidString, content: content, trigger: nil))
      } catch {
        logger.error("Failed to send notification: \(error.localizedDescription, privacy: .public)")
      }
    }

    // Episodes beyond the per-podcast cap get one summary so the count is honest.
    let remainder = totalCount - details.count
    if remainder > 0 {
      let content = UNMutableNotificationContent()
      content.title = "\(remainder) More New Episodes"
      content.body = "Open DoDo to see everything that just arrived."
      content.threadIdentifier = "newEpisodes"
      content.userInfo = ["type": "multipleEpisodes"]
      content.sound = .default
      try? await center.add(UNNotificationRequest(
        identifier: UUID().uuidString, content: content, trigger: nil))
    }

    logger.info("Sent \(details.count) episode notification(s), \(remainder) summarized")
  }

  /// Downloads podcast artwork to a temp file for use as a notification
  /// attachment. Best-effort: returns nil on any failure so the notification
  /// still fires without the thumbnail. UNNotificationAttachment copies the file
  /// into its own store, so the temp file can be discarded afterwards.
  ///
  /// The file type comes from the response MIME type, not the URL path: feed
  /// artwork is routinely served from extension-less URLs (or a `.jpg` path
  /// that returns PNG bytes), and UNNotificationAttachment rejects the file
  /// when the extension and the data disagree — the cause of artwork showing
  /// up only "sometimes".
  private func imageAttachment(from urlString: String?) async -> UNNotificationAttachment? {
    guard let urlString, !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        return nil
      }
      let type = Self.imageType(mimeType: response.mimeType, url: url, data: data)
      guard let type, let ext = type.preferredFilenameExtension else { return nil }
      // 10 MB is the system cap for image attachments; a bigger file is dropped
      // silently, so skip it and keep the plain notification.
      guard data.count <= 10 * 1024 * 1024 else { return nil }

      let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(ext)
      try data.write(to: tmp)
      return try UNNotificationAttachment(
        identifier: "artwork", url: tmp,
        options: [UNNotificationAttachmentOptionsTypeHintKey: type.identifier])
    } catch {
      logger.error("Artwork attachment failed: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  /// Resolve an image UTType from the response MIME type, falling back to the
  /// URL extension and then to the file's magic bytes.
  private static func imageType(mimeType: String?, url: URL, data: Data) -> UTType? {
    if let mimeType, let type = UTType(mimeType: mimeType), type.conforms(to: .image) {
      return type
    }
    if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
      return type
    }
    switch Array(data.prefix(4)) {
    case let b where b.starts(with: [0xFF, 0xD8, 0xFF]): return .jpeg
    case let b where b.starts(with: [0x89, 0x50, 0x4E, 0x47]): return .png
    case let b where b.starts(with: [0x47, 0x49, 0x46]): return .gif
    default: return nil
    }
  }

  /// HTML-ish feed description reduced to a short plain-text blurb for the
  /// expanded notification.
  static func plainSummary(_ raw: String?, limit: Int = 400) -> String? {
    guard let raw else { return nil }
    var text = raw.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                           ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
                           ("&nbsp;", " ")] {
      text = text.replacingOccurrences(of: entity, with: char)
    }
    text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    // Tags collapse to a space, which leaves "shop ." where markup hugged the
    // punctuation, so pull the space back out.
    text = text.replacingOccurrences(
      of: "\\s+([,.;:!?\u{2026}])", with: "$1", options: .regularExpression)
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    guard text.count > limit else { return text }
    return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "\u{2026}"
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
