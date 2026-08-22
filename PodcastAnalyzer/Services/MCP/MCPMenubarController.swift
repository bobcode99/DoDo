//
//  MCPMenubarController.swift
//  PodcastAnalyzer
//
//  Owns an NSStatusItem in the macOS menubar. Visible when the MCP server is
//  running OR when the app is in headless (accessory) mode. Doubles as the
//  re-entry point for headless mode ("Open main window").
//

#if os(macOS)
import AppKit
import SwiftUI
import Observation
import OSLog

@MainActor
final class MCPMenubarController {
  static let shared = MCPMenubarController()

  // AppStorage keys
  static let keyHeadless = "mcpHeadlessMode"
  static let keyLaunchAtLogin = "mcpLaunchAtLogin"

  private var statusItem: NSStatusItem?
  private var observationTask: Task<Void, Never>?
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "MCPMenubar")

  private init() {}

  // MARK: - Bootstrap

  /// Called once at app launch (macOS only). Sets up observation so the
  /// menubar icon appears/disappears as the server toggles or as headless
  /// mode is enabled.
  func bootstrap() {
    refresh()
    // Observe MCPServerManager via withObservationTracking on a recurring task.
    observationTask?.cancel()
    observationTask = Task { @MainActor in
      while !Task.isCancelled {
        // Re-arm observation tracking on each iteration; this is the standard
        // poll-then-rearm pattern for `withObservationTracking` since the
        // onChange closure fires only once.
        withObservationTracking {
          _ = MCPServerManager.shared.status
          _ = MCPServerManager.shared.enabled
          _ = UserDefaults.standard.bool(forKey: Self.keyHeadless)
        } onChange: {
          Task { @MainActor in
            MCPMenubarController.shared.refresh()
          }
        }
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  // MARK: - Rebuild

  func refresh() {
    let mgr = MCPServerManager.shared
    let headless = UserDefaults.standard.bool(forKey: Self.keyHeadless)
    let shouldShow = mgr.isRunning || headless

    if shouldShow {
      if statusItem == nil {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      }
      guard let item = statusItem else { return }

      if let button = item.button {
        // The DoDo mark, not SF Symbols' `network` globe. This item now stands
        // for the app itself — headless mode means the app is running with no
        // window — so a generic networking glyph named the wrong thing. Server
        // trouble is a badge on the mark; the tooltip and the menu header carry
        // the detail.
        var isError = false
        if case .error = mgr.status { isError = true }
        button.image = DoDoMenubarIcon.image(showsBadge: isError)
        button.image?.accessibilityDescription = isError ? "DoDo — server error" : "DoDo"
        button.toolTip = tooltip(for: mgr)
      }
      item.menu = buildMenu(for: mgr)
    } else {
      // Tear down so we don't leak a slot in the menubar.
      if let item = statusItem {
        NSStatusBar.system.removeStatusItem(item)
      }
      statusItem = nil
    }
  }

  // MARK: - Menu

  private func buildMenu(for mgr: MCPServerManager) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false

    let statusLine: String
    switch mgr.status {
    case .stopped:
      statusLine = "MCP server: stopped"
    case .running(let url):
      statusLine = "MCP server: \(url.host ?? "localhost"):\(url.port ?? 0)"
    case .error(let msg):
      statusLine = "MCP server error: \(msg)"
    }
    let header = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
    header.isEnabled = false
    menu.addItem(header)
    menu.addItem(.separator())

    let toggle = NSMenuItem(
      title: mgr.enabled ? "Stop MCP server" : "Start MCP server",
      action: #selector(toggleServer),
      keyEquivalent: ""
    )
    toggle.target = self
    menu.addItem(toggle)

    menu.addItem(.separator())

    let open = NSMenuItem(
      title: "Open Main Window",
      action: #selector(openMainWindow),
      keyEquivalent: "o"
    )
    open.target = self
    menu.addItem(open)

    let quit = NSMenuItem(
      title: "Quit PodcastAnalyzer",
      action: #selector(quitApp),
      keyEquivalent: "q"
    )
    quit.target = self
    menu.addItem(quit)

    return menu
  }

  private func tooltip(for mgr: MCPServerManager) -> String {
    switch mgr.status {
    case .stopped: return "MCP server: stopped"
    case .running(let url): return "MCP server: \(url.absoluteString)"
    case .error(let msg): return "MCP server error: \(msg)"
    }
  }

  // MARK: - Actions

  @objc private func toggleServer() {
    MCPServerManager.shared.enabled.toggle()
  }

  @objc private func openMainWindow() {
    MacBackgroundMode.presentMainWindow()
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }
}

#endif
