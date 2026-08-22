//
//  MacAppDelegate.swift
//  PodcastAnalyzer
//
//  The app had no NSApplicationDelegate at all, so nothing was in a position
//  to answer the two questions macOS asks every app: what to do at launch, and
//  what to do when someone opens an app that is already running.
//

#if os(macOS)

import AppKit
import OSLog
import SwiftUI

final class MacAppDelegate: NSObject, NSApplicationDelegate {
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "MacAppDelegate")

  func applicationDidFinishLaunching(_ notification: Notification) {
    MainActor.assumeIsolated {
      MacBackgroundMode.startObserving()

      guard shouldStayHidden(notification) else {
        MacBackgroundMode.presentMainWindow()
        return
      }
      logger.info("Login-item launch; staying in the menubar")
      MacBackgroundMode.apply()
    }
  }

  /// Only a launch macOS performed for the user at login starts without a
  /// window. Everything else — Finder, Spotlight, Dock, `open` — gets one.
  ///
  /// `launchIsDefaultUserInfoKey` is not a login-item test on its own: it also
  /// reports false when the app merely has saved state to restore, which is
  /// most launches of a long-lived app. Measured here with `open -a`, which is
  /// unambiguously a user launch and still reported false — so it is only
  /// consulted for users who actually asked for a login launch. Guessing wrong
  /// then shows a window, which is the direction that cannot strand anyone.
  private func shouldStayHidden(_ notification: Notification) -> Bool {
    guard UserDefaults.standard.bool(forKey: MCPMenubarController.keyLaunchAtLogin)
    else { return false }
    let isDefaultLaunch =
      notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
    return !isDefaultLaunch
  }

  /// Clicking the dock icon, or opening the app again from Finder or Spotlight.
  /// Returning true without a visible window used to do nothing at all in
  /// headless mode, which reads as the app being broken.
  func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    MainActor.assumeIsolated {
      if !flag { MacBackgroundMode.presentMainWindow() }
    }
    return true
  }

  /// Closing the last window leaves the app running so playback, downloads and
  /// the MCP server survive it — but only headless mode drops the dock icon,
  /// which `MacBackgroundMode` decides.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}

#endif
