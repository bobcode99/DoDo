//
//  MCPServerManager.swift
//  PodcastAnalyzer
//
//  Owns the lifecycle of the embedded MCP HTTP server. Observable so the
//  Settings UI and menubar controller can react to status / port / token
//  changes. Bound to the main actor (the rest of the app's singletons are too).
//

#if os(macOS)
import Foundation
import Observation
import SwiftData
import SwiftUI
import OSLog

@MainActor
@Observable
final class MCPServerManager {
  static let shared = MCPServerManager()

  // MARK: - AppStorage-mirrored settings
  // We mirror @AppStorage values into observable Swift properties so the
  // Settings UI binds against this single source of truth.

  /// Default port. Configurable in Preferences.
  static let defaultPort: Int = 7842

  var enabled: Bool {
    didSet {
      UserDefaults.standard.set(enabled, forKey: Self.keyEnabled)
      reconcile()
    }
  }
  var port: Int {
    didSet {
      UserDefaults.standard.set(port, forKey: Self.keyPort)
      // Port changed while running → restart.
      if enabled { reconcile(forceRestart: true) }
    }
  }
  /// Live bearer token (mirrors Keychain).
  var bearerToken: String

  // MARK: - Status

  enum Status: Equatable {
    case stopped
    case running(URL)
    case error(String)
  }

  private(set) var status: Status = .stopped

  // MARK: - AppStorage keys

  static let keyEnabled = "mcpServerEnabled"
  static let keyPort = "mcpServerPort"

  // MARK: - Internals

  private var modelContainer: ModelContainer?
  private var server: MCPHTTPServer?
  /// Owns the in-flight stop/start sequence so overlapping calls (rapid
  /// toggle, port edit while enabled) can't race and clobber `status`/`server`
  /// with a stale result. Each call cancels the previous Task before starting
  /// a new one; `start()` checks `Task.isCancelled` before it would otherwise
  /// overwrite state a newer reconcile already owns.
  private var reconcileTask: Task<Void, Never>?
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "MCPServerManager")

  // MARK: - Init

  private init() {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: Self.keyPort) == nil {
      defaults.set(Self.defaultPort, forKey: Self.keyPort)
    }
    self.enabled = defaults.bool(forKey: Self.keyEnabled)
    self.port = defaults.integer(forKey: Self.keyPort)
    self.bearerToken = MCPTokenStore.loadOrCreate()
  }

  // MARK: - Bootstrap (called from App init)

  func bootstrap(modelContainer: ModelContainer) {
    self.modelContainer = modelContainer
    reconcile()
    // Stop cleanly on app quit so the port is released.
    NotificationCenter.default.addObserver(
      forName: NSNotification.Name("NSApplicationWillTerminateNotification"),
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      Task { @MainActor in
        await self.stop()
      }
    }
  }

  // MARK: - Public actions

  /// Generates a new bearer token and replaces the current one.
  /// Restarts the server so the new token takes effect immediately.
  func regenerateToken() {
    let new = MCPTokenStore.regenerate()
    bearerToken = new
    if enabled { reconcile(forceRestart: true) }
  }

  /// Convenience for Settings UI — the URL clients should connect to.
  var connectionURL: URL? {
    URL(string: "http://127.0.0.1:\(port)/mcp")
  }

  /// Convenience for menubar UI.
  var isRunning: Bool {
    if case .running = status { return true }
    return false
  }

  // MARK: - Reconciliation

  private func reconcile(forceRestart: Bool = false) {
    reconcileTask?.cancel()
    reconcileTask = Task { @MainActor [weak self] in
      guard let self else { return }
      if self.enabled {
        if forceRestart || self.server == nil {
          await self.stop()
          guard !Task.isCancelled else { return }
          await self.start()
        }
      } else {
        await self.stop()
      }
    }
  }

  private func start() async {
    guard let container = modelContainer else {
      status = .error("Model container not initialized")
      return
    }
    let gateway = MCPDataGateway(modelContainer: container)
    let server = MCPHTTPServer(port: port, bearerToken: bearerToken)
    do {
      try await server.start(gateway: gateway)
      self.server = server
      if let url = connectionURL {
        status = .running(url)
        logger.info("MCP server running at \(url.absoluteString)")
      }
    } catch {
      logger.error("MCP server failed to start: \(error.localizedDescription, privacy: .public)")
      status = .error(error.localizedDescription)
      await server.stop()
      self.server = nil
    }
  }

  private func stop() async {
    await server?.stop()
    server = nil
    status = .stopped
  }
}

#endif
