//
//  PhoneWatchSession.swift
//  PodcastAnalyzer
//
//  The phone end of the watch link: pushes now-playing state out, applies
//  transport commands coming back.
//
//  Scoped to iOS — WatchConnectivity does not exist on macOS, and a Mac has no
//  paired watch to talk to. Everything durable (subscriptions, progress, Up
//  Next) syncs through CloudKit instead, so nothing here is load-bearing for
//  correctness; losing the link costs the watch a live scrubber, not data.
//

#if os(iOS)

import Foundation
import OSLog
import WatchConnectivity

private nonisolated let logger = Logger(subsystem: "com.podcast.analyzer", category: "WatchSession")

@MainActor
final class PhoneWatchSession: NSObject {
  static let shared = PhoneWatchSession()

  /// Last payload actually sent, so identical state is not pushed twice.
  /// `updateApplicationContext` replaces rather than queues, but each call
  /// still wakes the watch.
  private var lastSentSnapshot: WidgetPlaybackData?

  private override init() {
    super.init()
  }

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  // MARK: - Push

  func push(_ data: WidgetPlaybackData) {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated else { return }

    // Position moves constantly; the watch redraws its own clock between
    // pushes, so only send when something it cannot infer has changed.
    if let last = lastSentSnapshot,
      last.episodeTitle == data.episodeTitle,
      last.isPlaying == data.isPlaying,
      abs(last.currentTime - data.currentTime) < 5
    {
      return
    }

    guard let encoded = try? JSONEncoder().encode(data) else { return }
    do {
      try session.updateApplicationContext([WatchMessageKey.nowPlaying: encoded])
      lastSentSnapshot = data
    } catch {
      logger.error("Context push failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Receive

  private func apply(_ command: WatchCommand) {
    let manager = EnhancedAudioManager.shared
    switch command {
    case .togglePlayPause:
      manager.isPlaying ? manager.pause() : manager.resume()
    case .skipForward:
      manager.skipForward()
    case .skipBackward:
      manager.skipBackward()
    case .seek(let time):
      manager.seek(to: time)
    case .setRate(let rate):
      manager.setPlaybackRate(rate)
    }
  }

}

/// Decoded off the main actor so only the `Sendable` result crosses the hop —
/// a `[String: Any]` cannot cross one at all.
private nonisolated func decodeCommand(from message: [String: Any]) -> WatchCommand? {
  guard let data = message[WatchMessageKey.command] as? Data else { return nil }
  return try? JSONDecoder().decode(WatchCommand.self, from: data)
}

extension PhoneWatchSession: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error {
      logger.error("Activation failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    guard let command = decodeCommand(from: message) else { return }
    Task { @MainActor in self.apply(command) }
  }

  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    guard let command = decodeCommand(from: userInfo) else { return }
    Task { @MainActor in self.apply(command) }
  }

  // Required on iOS: the pairing can change under us.
  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

  nonisolated func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }
}

#endif
