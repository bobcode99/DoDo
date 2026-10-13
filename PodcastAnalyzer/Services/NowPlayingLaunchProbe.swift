//
//  NowPlayingLaunchProbe.swift
//  PodcastAnalyzer
//
//  TEMPORARY device probe (DEBUG, iOS). Records every launch signal the system
//  can hand the app, to check whether opening from system Now Playing (Dynamic
//  Island, Control Center, Lock Screen) differs from tapping the app icon.
//  Also tags Now Playing with the show's App Entity (iOS 27) to see whether a
//  tap is routed through ProbeOpenPodcastIntent. Output: Documents/np-probe.txt.
//  Delete this file and its `NowPlayingLaunchProbe` hooks after the test.
//

#if DEBUG && os(iOS)
import AppIntents
import MediaPlayer
import UIKit

nonisolated enum NowPlayingLaunchProbe {
  private static let fileURL = URL.documentsDirectory.appending(path: "np-probe.txt")

  static func log(_ message: String) {
    let line = "\(Date.now.formatted(.iso8601.time(includingFractionalSeconds: true))) \(message)\n"
    print("[NPProbe] \(line)", terminator: "")
    let data = Data(line.utf8)
    if let handle = try? FileHandle(forWritingTo: fileURL) {
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: fileURL)
    }
  }

  static func startObserving() {
    let names: [Notification.Name] = [
      UIApplication.willEnterForegroundNotification,
      UIApplication.didBecomeActiveNotification,
      UIApplication.willResignActiveNotification,
      UIApplication.didEnterBackgroundNotification,
      UIApplication.protectedDataDidBecomeAvailableNotification,
      UIApplication.protectedDataWillBecomeUnavailableNotification,
    ]
    for name in names {
      _ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
        log("notification \(name.rawValue)")
      }
    }
  }

  @MainActor
  static func describe(_ options: UIScene.ConnectionOptions) -> String {
    let urls = options.urlContexts.map { "\($0.url) src=\($0.options.sourceApplication ?? "nil")" }
    return "urls=\(urls) activities=\(options.userActivities.map(\.activityType))"
      + " handoff=\(options.handoffUserActivityType ?? "nil")"
      + " shortcut=\(options.shortcutItem?.type ?? "nil")"
      + " source=\(options.sourceApplication ?? "nil")"
      + " notification=\(options.notificationResponse?.actionIdentifier ?? "nil")"
  }

  @MainActor
  static func addEntityIdentifier(to info: inout [String: Any], podcastTitle: String) {
    guard #available(iOS 27.0, *),
          let rssUrl = PlaybackStateCoordinator.shared?.feedURL(forPodcastTitle: podcastTitle),
          let id = MPAppEntityIdentifier(
            entityIdentifier: EntityIdentifier(for: PodcastAppEntity.self, identifier: rssUrl))
    else {
      log("entity id not set for \(podcastTitle)")
      return
    }
    info[MPNowPlayingInfoPropertyAppEntityIdentifiers] = [id]
  }
}

final class NowPlayingProbeAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    NowPlayingLaunchProbe.log(
      "didFinishLaunching options=\(launchOptions?.keys.map(\.rawValue) ?? []) state=\(application.applicationState.rawValue)")
    NowPlayingLaunchProbe.startObserving()
    return true
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    NowPlayingLaunchProbe.log("configurationForConnecting \(NowPlayingLaunchProbe.describe(options))")
    let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    if connectingSceneSession.role == .windowApplication {
      configuration.delegateClass = NowPlayingProbeSceneDelegate.self
    }
    return configuration
  }
}

/// No `scene(_:openURLContexts:)` here: implementing it would take URLs away
/// from SwiftUI's `.onOpenURL`, which logs them instead.
final class NowPlayingProbeSceneDelegate: NSObject, UIWindowSceneDelegate {
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    NowPlayingLaunchProbe.log("willConnect \(NowPlayingLaunchProbe.describe(connectionOptions))")
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    NowPlayingLaunchProbe.log("sceneWillEnterForeground")
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    NowPlayingLaunchProbe.log("sceneDidBecomeActive")
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    NowPlayingLaunchProbe.log("sceneDidEnterBackground")
  }

  func scene(_ scene: UIScene, willContinueUserActivityWithType userActivityType: String) {
    NowPlayingLaunchProbe.log("willContinueUserActivity \(userActivityType)")
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    NowPlayingLaunchProbe.log(
      "continueUserActivity \(userActivity.activityType) url=\(userActivity.webpageURL?.absoluteString ?? "nil") keys=\(userActivity.userInfo?.keys.map { "\($0)" } ?? [])")
  }

  func windowScene(
    _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem
  ) async -> Bool {
    NowPlayingLaunchProbe.log("shortcutItem \(shortcutItem.type)")
    return false
  }
}

/// Runs only if the system opens Now Playing's tagged entity through App Intents.
struct ProbeOpenPodcastIntent: OpenIntent {
  static let title = LocalizedStringResource("Open Podcast (Probe)", table: "Probe")

  @Parameter(title: LocalizedStringResource("Podcast", table: "Probe"))
  var target: PodcastAppEntity

  @MainActor
  func perform() async throws -> some IntentResult {
    NowPlayingLaunchProbe.log("ProbeOpenPodcastIntent target=\(target.title)")
    NotificationNavigationManager.shared.requestExpandPlayer()
    return .result()
  }
}
#endif
