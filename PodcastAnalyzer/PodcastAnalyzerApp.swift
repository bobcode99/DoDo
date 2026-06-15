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

  let sharedModelContainer: ModelContainer = {
    let schema = Schema([
      PodcastInfoModel.self,
      EpisodeDownloadModel.self,
      EpisodeAIAnalysis.self,
      EpisodeQuickTagsModel.self,
      QueueItemModel.self,
    ])
    let modelConfiguration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: false,
      cloudKitDatabase: .none
    )

    do {
      return try ModelContainer(for: schema, configurations: [modelConfiguration])
    } catch {
      // The project intentionally ships no schema migrations — a schema change
      // is allowed to reset the local store (see CLAUDE.md). Rather than brick
      // the app on a migration failure, delete the incompatible store (and its
      // -wal/-shm sidecars) and rebuild it from scratch. This is what makes
      // future schema changes (indexes, #Unique, new properties) safe to ship.
      logger.error("ModelContainer init failed, rebuilding store: \(error.localizedDescription)")
      let storeURL = modelConfiguration.url
      let fm = FileManager.default
      try? fm.removeItem(at: storeURL)
      try? fm.removeItem(at: URL(fileURLWithPath: storeURL.path + "-wal"))
      try? fm.removeItem(at: URL(fileURLWithPath: storeURL.path + "-shm"))
      do {
        return try ModelContainer(for: schema, configurations: [modelConfiguration])
      } catch {
        logger.error("ModelContainer rebuild failed: \(error.localizedDescription)")
        fatalError("Could not create ModelContainer even after store reset: \(error)")
      }
    }
  }()

  init() {
    // Configure Nuke image pipeline with persistent data cache
    configureImagePipeline()

    // Register background task for episode sync
    BackgroundSyncManager.registerBackgroundTask()

    // Eagerly start NWPathMonitor at launch. NetworkMonitor.shared is lazy
    // (singleton), and its `isConnected` defaults to false until the first
    // path update fires — touching it here kicks off monitoring during init
    // so playback gating later sees an accurate value.
    _ = NetworkMonitor.shared

    // Export previous session's os.log entries to Documents/Logs
    PersistentLogService.shared.exportLogsInBackground()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(\.locale, languageManager.locale)
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

          // Migrate flat caption files to podcast subfolders (one-time, safe to re-run)
          Task.detached(priority: .utility) {
            await FileStorageManager.shared.migrateFlatCaptionFilesToSubfolders()
          }

          // macOS: embed the MCP HTTP server and set up the menubar controller.
          // Both honor the user's Preferences toggles; neither runs unless asked.
          #if os(macOS)
          MCPServerManager.shared.bootstrap(modelContainer: sharedModelContainer)
          MCPMenubarController.shared.bootstrap()
          if UserDefaults.standard.bool(forKey: MCPMenubarController.keyHeadless) {
            NSApp.setActivationPolicy(.accessory)
          }
          #endif

          // Handle any pending widget toggle (pause) flag from cold launch.
          EnhancedAudioManager.shared.handleWidgetToggleOnActive()

          // Force Siri to re-read AppShortcut phrases + suggested entities so
          // phrase mappings stay current after a fresh install or app update.
          // Cheap to call; no-op on Siri's side if nothing changed.
          PodcastAnalyzerShortcuts.updateAppShortcutParameters()

          // Request critical permissions early so they don't interrupt mid-session
          #if os(iOS)
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
          #endif

          // Register low-memory warning handler to clear caches
          #if os(iOS)
          NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
          ) { _ in
            Task { @MainActor in
              ImageCacheUtility.clearMemoryCache()
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

    // Handle widget deep links
    if url.scheme == "podcastanalyzer" {
      Task { @MainActor in
        switch url.host {
        case "import-podcasts":
          // Callback from "ApplePodcast To PodcastAnalyzer" shortcut.
          // Expected format: podcastanalyzer://import-podcasts?rssURLs=url1,url2,...
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
}
