//
//  MacBackgroundMode.swift
//  PodcastAnalyzer
//
//  Owns the macOS activation policy, and the question the app previously never
//  asked: did the user actually ask for a window?
//
//  "Run as menubar app" used to set .accessory during App.init, before any
//  window existed, on every launch. That is correct for a login item and wrong
//  for everything else — double-clicking the app started it with no dock icon,
//  no menu bar and no window, and the only way back in was noticing the
//  menubar glyph. The toggle now governs what happens when the last window
//  closes, not whether the app is allowed to show one.
//

#if os(macOS)

import AppKit
import OSLog

@MainActor
enum MacBackgroundMode {
  private static let logger = Logger(
    subsystem: "com.podcast.analyzer", category: "MacBackgroundMode")

  private static var windowObserver: NSObjectProtocol?

  static var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: MCPMenubarController.keyHeadless)
  }

  // MARK: - Policy

  /// Accessory only while headless is on *and* nothing is on screen. An app
  /// with a window open wants its dock icon and its menu bar; SwiftUI puts
  /// File and Edit there, and an accessory app has neither.
  static func apply() {
    let policy = policy(headless: isEnabled, hasVisibleWindow: hasVisibleWindow)
    guard NSApp.activationPolicy() != policy else { return }
    NSApp.setActivationPolicy(policy)
    logger.info("Activation policy → \(policy == .accessory ? "accessory" : "regular", privacy: .public)")
  }

  /// The whole rule, separated from `NSApp` so it can be exercised without a
  /// running application — the window-closing half is not scriptable.
  static func policy(headless: Bool, hasVisibleWindow: Bool) -> NSApplication.ActivationPolicy {
    (headless && !hasVisibleWindow) ? .accessory : .regular
  }

  /// Titled windows only. The status item and SwiftUI's various helper
  /// surfaces are borderless or panels, and counting them would pin the app to
  /// .regular forever — headless mode would silently never engage.
  static var hasVisibleWindow: Bool {
    NSApp.windows.contains(where: isUserFacing)
  }

  private static func isUserFacing(_ window: NSWindow) -> Bool {
    window.isVisible && window.styleMask.contains(.titled) && !(window is NSPanel)
  }

  // MARK: - Presenting

  /// Brings the app forward with a window, whatever policy it was in.
  static func presentMainWindow() {
    NSApp.setActivationPolicy(.regular)

    if let window = NSApp.windows.first(where: isUserFacing) {
      window.makeKeyAndOrderFront(nil)
      logger.info("Presented existing window")
    } else {
      logger.info("No window to present; asking the scene for a new one")
      // Every window was closed. `newDocument:` is what SwiftUI's WindowGroup
      // installs behind File ▸ New Window, so this asks the scene for a fresh
      // one rather than trying to resurrect an NSWindow it no longer owns.
      NSDocumentController.shared.newDocument(nil)
    }

    NSApp.activate(ignoringOtherApps: true)
  }

  // MARK: - Observation

  /// Re-evaluates the policy whenever a window closes, which is the only
  /// moment headless mode can legitimately take the dock icon away.
  static func startObserving() {
    guard windowObserver == nil else { return }
    windowObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: nil, queue: .main
    ) { _ in
      // "will" close: the window is still in NSApp.windows and still visible,
      // so the decision has to wait a turn. Getting this wrong leaves the app
      // .regular, which is the harmless direction — a visible dock icon, not a
      // vanished app.
      Task { @MainActor in apply() }
    }
  }
}

#endif
