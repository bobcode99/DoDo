//
//  WatchSessionManager.swift
//  DoDoWatch
//
//  The watch end of the phone link. Only two jobs: hold the latest now-playing
//  snapshot the phone pushed, and send transport commands back.
//
//  Everything durable — subscriptions, progress, Up Next — travels through
//  CloudKit instead, which is why this file is a fraction of the size of
//  Pocket Casts' SessionManager + WatchDataManager pair.
//

import Foundation
import Observation
import OSLog
import WatchConnectivity

private nonisolated let logger = Logger(subsystem: "com.jn.PodcastAnalyzer.watch", category: "Connectivity")

@MainActor
@Observable
final class WatchSessionManager: NSObject {
  static let shared = WatchSessionManager()

  /// Last state the phone pushed. Nil until the first context arrives.
  private(set) var nowPlaying: WidgetPlaybackData?
  private(set) var isReachable = false

  private override init() {
    super.init()
  }

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
    // A context delivered while the app was not running is waiting here.
    if let snapshot = decodeSnapshot(from: session.receivedApplicationContext) {
      apply(snapshot)
    }
  }

  // MARK: - Sending

  func send(_ command: WatchCommand) {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard let data = try? JSONEncoder().encode(command) else { return }
    let message = [WatchMessageKey.command: data]

    if session.isReachable {
      session.sendMessage(message, replyHandler: nil) { error in
        logger.error("Command send failed: \(error.localizedDescription, privacy: .public)")
      }
    } else {
      // Queued for the next time the phone is awake. Transport commands are
      // near-useless late, but delivering a stale pause beats silently
      // dropping the tap.
      session.transferUserInfo(message)
    }
  }

  // MARK: - Receiving

  private func apply(_ snapshot: WidgetPlaybackData) {
    nowPlaying = snapshot
  }
}

/// Decoded off the main actor so only the `Sendable` result crosses the hop —
/// a `[String: Any]` cannot cross one at all.
private nonisolated func decodeSnapshot(from context: [String: Any]) -> WidgetPlaybackData? {
  guard let data = context[WatchMessageKey.nowPlaying] as? Data else { return nil }
  return try? JSONDecoder().decode(WidgetPlaybackData.self, from: data)
}

extension WatchSessionManager: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error {
      logger.error("Activation failed: \(error.localizedDescription, privacy: .public)")
    }
    let reachable = session.isReachable
    Task { @MainActor in self.isReachable = reachable }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    guard let snapshot = decodeSnapshot(from: context) else { return }
    Task { @MainActor in self.apply(snapshot) }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    Task { @MainActor in self.isReachable = reachable }
  }
}
