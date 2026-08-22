//
//  PodcastAnalyzerApp.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/11/12.
//

import AppIntents
import OSLog
import Speech
import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "App")

@main
struct PodcastAnalyzerApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @State private var languageManager = LanguageManager.shared

  #if os(macOS)
  /// Owns launch and reopen. SwiftUI alone answers neither: a WindowGroup does
  /// not distinguish a login-item launch from a double-click, and it has no
  /// hook at all for "the app is already running and someone opened it again".
  @NSApplicationDelegateAdaptor private var appDelegate: MacAppDelegate
  #endif

  /// Whether to auto-present the expanded player when the user brings the app
  /// to the foreground while it is still playing. This is how Apple Podcasts
  /// makes tapping the Dynamic Island / Now Playing controls land on the
  /// player: iOS gives no "opened from Now Playing" signal, so we approximate
  /// it by opening the player whenever a playing app is foregrounded.
  @AppStorage("openPlayerOnReturnToPlayback") private var openPlayerOnReturnToPlayback = true

  /// Captured at backgrounding so we only auto-open the player when the app
  /// was *actively playing* as it left (and still is on return) — not on cold
  /// launches or returns from a paused state.
  @State private var wasPlayingOnBackground = false

  /// CloudKit container shared by every device signed into the same Apple ID.
  static let cloudKitContainerIdentifier = "iCloud.com.jn.PodcastAnalyzer"

  let sharedModelContainer: ModelContainer = {
    let fullSchema = Schema([
      PodcastInfoModel.self,
      EpisodeDownloadModel.self,
      EpisodeAIAnalysis.self,
      EpisodeQuickTagsModel.self,
      QueueItemModel.self,
      PlaybackProgressModel.self,
      EpisodeTranscriptModel.self,
      SubscribedPodcastModel.self,
    ])

    // Local-only store: unchanged from before. Kept off CloudKit because it
    // carries device-specific state (downloaded file paths) that would be
    // meaningless — or actively wrong — synced to another device.
    let localConfiguration = ModelConfiguration(
      "local",
      schema: Schema([
        PodcastInfoModel.self,
        EpisodeDownloadModel.self,
        EpisodeQuickTagsModel.self,
        EpisodeTranscriptModel.self,
      ]),
      isStoredInMemoryOnly: false,
      cloudKitDatabase: .none
    )

    // CloudKit-synced store: playback progress, subscribed-podcast pointers
    // (rssUrl/title only, not the full episode blob — PodcastInfoModel's RSS
    // snapshot risks CloudKit's 1MB-per-record cap for large back-catalogs),
    // AI analyses (text JSON, comfortably under the record cap), and the Up
    // Next queue mirrored to the user's private database.
    //
    // QueueItemModel is here rather than in the local store because it is how
    // the watch app reads Up Next — the watch shares this container, and an
    // App Group would not reach it. The row is already CloudKit-legal: no
    // relationships, no #Unique, every property defaulted.
    let cloudConfiguration = ModelConfiguration(
      "cloud",
      schema: Schema([
        PlaybackProgressModel.self,
        SubscribedPodcastModel.self,
        EpisodeAIAnalysis.self,
        QueueItemModel.self,
      ]),
      isStoredInMemoryOnly: false,
      cloudKitDatabase: .private(cloudKitContainerIdentifier)
    )

    do {
      return try ModelContainer(for: fullSchema, configurations: [localConfiguration, cloudConfiguration])
    } catch {
      // The project intentionally ships no schema migrations — a schema change
      // is allowed to reset the local store (see CLAUDE.md). Rather than brick
      // the app on a migration failure, delete the incompatible stores (and their
      // -wal/-shm sidecars) and rebuild them from scratch. This is what makes
      // future schema changes (indexes, #Unique, new properties) safe to ship.
      logger.error("ModelContainer init failed, rebuilding store: \(error.localizedDescription, privacy: .public)")
      let fm = FileManager.default
      for configuration in [localConfiguration, cloudConfiguration] {
        let storeURL = configuration.url
        try? fm.removeItem(at: storeURL)
        try? fm.removeItem(at: URL(fileURLWithPath: storeURL.path + "-wal"))
        try? fm.removeItem(at: URL(fileURLWithPath: storeURL.path + "-shm"))
      }
      do {
        return try ModelContainer(for: fullSchema, configurations: [localConfiguration, cloudConfiguration])
      } catch {
        logger.error("ModelContainer rebuild failed: \(error.localizedDescription, privacy: .public)")
        fatalError("Could not create ModelContainer even after store reset: \(error)")
      }
    }
  }()

  init() {
    // Configure Nuke image pipeline with persistent data cache
    configureImagePipeline()

    // Register background task for episode sync
    BackgroundSyncManager.registerBackgroundTask()

    // Containers must be wired here, not only in WindowGroup.task: on a cold
    // BGAppRefreshTask launch the scene never connects, .task never runs, and
    // performSync bails with "ModelContainer not set" — background refresh
    // silently did nothing for terminated apps. Setters are idempotent; the
    // .task calls below stay as belt-and-braces.
    BackgroundSyncManager.shared.setModelContainer(sharedModelContainer)
    DownloadManager.shared.setModelContainer(sharedModelContainer)
    TranscriptManager.shared.setModelContainer(sharedModelContainer)
    PlaybackProgressSyncCoordinator.shared.setModelContainer(sharedModelContainer)
    SubscriptionSyncCoordinator.shared.setModelContainer(sharedModelContainer)
    TranscriptStore.shared.setModelContainer(sharedModelContainer)
    AppIntentsModelStore.container = sharedModelContainer
    #if os(iOS)
    PhoneWatchSession.shared.activate()
    #endif

    // Show new-episode banners in foreground + route taps to episode detail.
    UNUserNotificationCenter.current().delegate = NotificationTapDelegate.shared

    // Eagerly start NWPathMonitor at launch. NetworkMonitor.shared is lazy
    // (singleton), and its `isConnected` defaults to false until the first
    // path update fires — touching it here kicks off monitoring during init
    // so playback gating later sees an accurate value.
    _ = NetworkMonitor.shared

    // Activation policy is deliberately not touched here. Setting .accessory
    // during init — before any window exists — hid the app on every launch,
    // including the ones the user asked for. MacAppDelegate decides it from
    // the launch reason instead.
  }

  /// Set after a ".dodotranscript" file import attempt; drives the result alert.
  @State private var transcriptImportMessage: String?

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(\.locale, languageManager.locale)
        .alert(
          "Transcript Import",
          isPresented: Binding(
            get: { transcriptImportMessage != nil },
            set: { if !$0 { transcriptImportMessage = nil } }
          )
        ) {
          Button("OK", role: .cancel) {}
        } message: {
          Text(transcriptImportMessage ?? "")
        }
        .task {
          // Critical: initialize playback state and sync manager first
          if PlaybackStateCoordinator.shared == nil {
            _ = PlaybackStateCoordinator(modelContext: sharedModelContainer.mainContext)
          }
          // Restore queue if it was deferred (ContentView.onAppear ran before coordinator init)
          EnhancedAudioManager.shared.restoreQueueIfNeeded()
          BackgroundSyncManager.shared.setModelContainer(sharedModelContainer)

          // Start foreground sync if enabled
          if BackgroundSyncManager.shared.isBackgroundSyncEnabled {
            BackgroundSyncManager.shared.startForegroundSync()
            BackgroundSyncManager.shared.scheduleBackgroundRefresh()
          }

          // Deferred: non-critical managers initialized after first frame
          PodcastImportManager.shared.setModelContainer(sharedModelContainer)
          NotificationNavigationManager.shared.setModelContainer(sharedModelContainer)
          DownloadManager.shared.setModelContainer(sharedModelContainer)
          TranscriptManager.shared.setModelContainer(sharedModelContainer)

          // Opt-in cleanup of finished episodes (24h grace; see sweep docs).
          DownloadManager.shared.sweepPlayedDownloads()

          // macOS: embed the MCP HTTP server and set up the menubar controller.
          // Both honor the user's Preferences toggles; neither runs unless asked.
          #if os(macOS)
          MCPServerManager.shared.bootstrap(modelContainer: sharedModelContainer)
          MCPMenubarController.shared.bootstrap()
          #endif

          // Handle any pending widget toggle (pause) flag from cold launch.
          EnhancedAudioManager.shared.handleWidgetToggleOnActive()

          // Force Siri to re-read AppShortcut phrases + suggested entities so
          // phrase mappings stay current after a fresh install or app update.
          // Cheap to call; no-op on Siri's side if nothing changed.
          PodcastAnalyzerShortcuts.updateAppShortcutParameters()

          // Request critical permissions early so they don't interrupt mid-session.
          // Only for users who already finished onboarding — new users grant these
          // deliberately on the onboarding Permissions page, so don't ambush them
          // with system prompts on first launch.
          #if os(iOS)
          if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            // Speech recognition (used by on-device transcription).
            // Must be detached: requestAuthorization delivers its callback on a non-main
            // thread, which would crash under Swift 6 MainActor isolation if called inline.
            Task.detached(priority: .utility) {
              SFSpeechRecognizer.requestAuthorization { _ in }
            }
            // Notification permission if enabled in settings
            if BackgroundSyncManager.shared.isNotificationsEnabled {
              BackgroundSyncManager.shared.requestNotificationPermission()
            }
            // Trigger paste permission prompt (used by AI Shortcuts clipboard fallback)
            _ = UIPasteboard.general.hasStrings
          }
          #endif

          // Register low-memory warning handler to clear caches
          #if os(iOS)
          NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
          ) { _ in
            Task { @MainActor in
              ImageCacheUtility.clearAllCache()
              await RSSCacheService.shared.clearAllCache()
              logger.warning("Low memory warning: cleared image and RSS caches")
            }
          }
          #endif
        }
        .onOpenURL { url in
          // Handle URL callbacks from Shortcuts
          handleIncomingURL(url)
        }
    }
    .modelContainer(sharedModelContainer)
    .onChange(of: scenePhase) { _, newPhase in
      switch newPhase {
      case .active:
        // App became active - handle widget toggle (pause) flag if pending
        EnhancedAudioManager.shared.handleWidgetToggleOnActive()
        // Opt-in cleanup of finished episodes (self-throttled to hourly).
        DownloadManager.shared.sweepPlayedDownloads()
        // Re-anchor the app icon badge to the inbox's unread count. Also clears
        // badges stranded by older builds that set but never cleared them.
        NotificationInbox.shared.syncBadge()
        // Force widget to re-read latest playback data every time app becomes active
        WidgetCenter.shared.reloadAllTimelines()
        // Start foreground sync
        if BackgroundSyncManager.shared.isBackgroundSyncEnabled {
          BackgroundSyncManager.shared.startForegroundSync()
        }
        #if os(iOS)
        // Returned to a still-playing app (e.g. tapped the Dynamic Island /
        // Now Playing controls) → surface the expanded player, Apple Podcasts
        // style. handleWidgetToggleOnActive() above already applied any pending
        // pause, so isPlaying here reflects the real post-activation state.
        if openPlayerOnReturnToPlayback,
           wasPlayingOnBackground,
           EnhancedAudioManager.shared.isPlaying,
           EnhancedAudioManager.shared.currentEpisode != nil {
          Task { @MainActor in
            // Let the foreground transition settle before presenting the sheet.
            try? await Task.sleep(for: .milliseconds(350))
            NotificationNavigationManager.shared.requestExpandPlayer()
          }
        }
        wasPlayingOnBackground = false
        #endif
      case .background:
        // App going to background - stop foreground timer, schedule background task
        BackgroundSyncManager.shared.stopForegroundSync()
        if BackgroundSyncManager.shared.isBackgroundSyncEnabled {
          BackgroundSyncManager.shared.scheduleBackgroundRefresh()
        }
        // Export this session's os.log entries to Documents/Logs now, while the
        // process is still alive. OSLogStore(.currentProcessIdentifier) can only
        // see the current process, so this must run at the end of a session — not
        // at launch, when nothing has been logged yet.
        PersistentLogService.shared.exportLogsInBackground()
        // Flush playback progress to iCloud immediately rather than waiting on
        // the throttle window — otherwise another device could see a stale
        // "continue listening" position for up to 30s after backgrounding.
        if EnhancedAudioManager.shared.currentEpisode != nil {
          EnhancedAudioManager.shared.syncPlaybackProgressNow()
        }
        #if os(iOS)
        // Remember whether we left mid-playback so .active can decide whether
        // to auto-open the player on return.
        wasPlayingOnBackground = EnhancedAudioManager.shared.isPlaying
        #endif
      case .inactive:
        break
      @unknown default:
        break
      }
    }

    // macOS Settings window (Cmd+,)
    #if os(macOS)
    Settings {
      MacSettingsView()
        .environment(\.locale, languageManager.locale)
    }
    .modelContainer(sharedModelContainer)
    #endif
  }

  private func handleIncomingURL(_ url: URL) {
    logger.info("Received URL: \(url.absoluteString)")

    // ".dodotranscript" file from another DoDo install (AirDrop, WhatsApp…).
    if url.pathExtension == TranscriptStore.shareFileExtension {
      let accessing = url.startAccessingSecurityScopedResource()
      defer { if accessing { url.stopAccessingSecurityScopedResource() } }
      do {
        let data = try Data(contentsOf: url)
        let (podcast, episode) = try TranscriptStore.shared.importShareFile(data: data)
        transcriptImportMessage = "Transcript for “\(episode)” (\(podcast)) imported."
      } catch {
        logger.error("Transcript import failed: \(error.localizedDescription, privacy: .public)")
        transcriptImportMessage = "Couldn't import transcript: \(error.localizedDescription)"
      }
      return
    }

    // Handle widget deep links
    if url.scheme == "podcastanalyzer" {
      Task { @MainActor in
        switch url.host {
        case "import-podcasts":
          // Callback from "ApplePodcast To PodcastAnalyzer" shortcut.
          // Expected format: podcastanalyzer://import-podcasts?rssURLs=url1,url2,...
          // Importing *is* completing setup — land on the home screen, not back
          // on the onboarding page the user launched the shortcut from.
          UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
          if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
             let rawValue = components.queryItems?.first(where: { $0.name == "rssURLs" })?.value {
            let rssURLs = rawValue
              .components(separatedBy: CharacterSet(charactersIn: ",\n"))
              .map { $0.trimmingCharacters(in: .whitespaces) }
              .filter { !$0.isEmpty }
            if !rssURLs.isEmpty {
              await PodcastImportManager.shared.importPodcasts(from: rssURLs)
            }
          }

        case "episode":
          // Widget tap with audio URL: podcastanalyzer://episode?audio=<encoded_url>
          if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
             let audioParam = components.queryItems?.first(where: { $0.name == "audio" })?.value {
            NotificationNavigationManager.shared.navigateToEpisode(audioURL: audioParam)
          }
        case "episodedetail":
          // Widget background tap: navigate to episode detail screen
          if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            let params = Dictionary(
              uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
              }
            )
            NotificationNavigationManager.shared.navigateToEpisodeDetail(
              title: params["title"] ?? "",
              podcastTitle: params["podcast"] ?? "",
              audioURL: params["audio"] ?? "",
              imageURL: params["image"] ?? ""
            )
          }
        case "open-shared-link":
          // "Open in DoDo" share extension: podcastanalyzer://open-shared-link?url=<shared link>
          if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
             let shared = components.queryItems?.first(where: { $0.name == "url" })?.value {
            await openSharedApplePodcastsLink(shared)
          }
        case "expandplayer":
          // Widget tap: open expanded player directly
          NotificationNavigationManager.shared.requestExpandPlayer()
        case "nowplaying":
          // Navigate to currently playing episode
          NotificationNavigationManager.shared.navigateToNowPlaying()
        case "library":
          // Just open the app to library (no specific navigation needed)
          break
        default:
          // Fall back to Shortcuts handling
          ShortcutsAIService.shared.handleURL(url)
        }
      }
    } else {
      // Route to ShortcutsAIService for handling
      Task { @MainActor in
        ShortcutsAIService.shared.handleURL(url)
      }
    }
  }

  /// Resolve an Apple Podcasts episode link (…/podcast/name/id<podcastID>?i=<episodeID>)
  /// via the iTunes Lookup API and navigate straight to the episode detail page.
  private func openSharedApplePodcastsLink(_ link: String) async {
    guard let url = URL(string: link),
          let idComponent = url.pathComponents.last(where: { $0.hasPrefix("id") }),
          let podcastId = Int(idComponent.dropFirst(2))
    else {
      logger.warning("Shared link is not an Apple Podcasts link: \(link)")
      return
    }

    // ponytail: podcast-only links (no ?i=) just open the app; add podcast
    // navigation when someone actually shares one.
    guard let episodeIdString = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "i" })?.value,
          let episodeId = Int(episodeIdString)
    else { return }

    do {
      let episodes = try await ApplePodcastService().fetchEpisodes(for: podcastId)
      guard let episode = episodes.first(where: { $0.trackId == episodeId }) else {
        logger.warning("Episode \(episodeId) not found in lookup for podcast \(podcastId)")
        return
      }
      NotificationNavigationManager.shared.navigateToEpisodeDetail(
        title: episode.trackName,
        podcastTitle: episode.collectionName ?? "",
        audioURL: episode.episodeUrl ?? episode.previewUrl ?? "",
        imageURL: episode.artworkUrl600 ?? episode.artworkUrl160 ?? ""
      )
    } catch {
      logger.error("Failed to resolve shared episode link: \(error.localizedDescription)")
    }
  }
}
