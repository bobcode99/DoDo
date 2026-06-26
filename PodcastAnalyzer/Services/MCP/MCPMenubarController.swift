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
        let symbolName: String
        if case .error = mgr.status {
          symbolName = "exclamationmark.triangle"
        } else if mgr.isRunning {
          symbolName = "network"
        } else {
          symbolName = "network.slash"
        }
        button.image = NSImage(
          systemSymbolName: symbolName,
          accessibilityDescription: "PodcastAnalyzer MCP"
        )
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
    // Bring app forward and open or focus the main window.
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    // The first WindowGroup window is typically already created; if hidden,
    // bring it forward. If it was closed in accessory mode, recreate it.
    for window in NSApp.windows where !(window is NSPanel) {
      window.makeKeyAndOrderFront(nil)
    }
    if NSApp.windows.allSatisfy({ ($0 is NSPanel) || !$0.isVisible }) {
      // No visible window — ask the runtime to open one for our default scene.
      NSDocumentController.shared.newDocument(nil)
    }
  }

  @objc private func quitApp() {
    NSApp.terminate(nil)
  }
}

#endif
