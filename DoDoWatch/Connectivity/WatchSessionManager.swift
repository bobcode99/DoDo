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
import WidgetKit

private nonisolated let logger = Logger(subsystem: "com.jn.PodcastAnalyzer.watch", category: "Connectivity")

@MainActor
@Observable
final class WatchSessionManager: NSObject {
  static let shared = WatchSessionManager()

  /// Last state the phone pushed. Nil until the first context arrives.
  private(set) var nowPlaying: WidgetPlaybackData?
  /// The phone's Up Next, in its order. Empty until the phone sends one.
  private(set) var upNext: [PlaybackEpisode] = []
  private(set) var isReachable = false

  private override init() {
    super.init()
  }

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
    // Nothing else belongs here. `activate()` is asynchronous, and every other
    // member of WCSession — receivedApplicationContext, isReachable,
    // sendMessage, transferUserInfo — no-ops and logs
    // "WCSession has not been activated" until the delegate callback lands.
    // Reading the waiting context and asking for state both moved into
    // `session(_:activationDidCompleteWith:error:)`.
  }

  // MARK: - Sending

  func send(_ command: WatchCommand) {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated else {
      logger.error("Not activated; dropping command")
      return
    }
    guard let data = try? JSONEncoder().encode(command) else { return }
    let message = [WatchMessageKey.command: data]

    if session.isReachable {
      session.sendMessage(message, replyHandler: nil) { error in
        logger.error("Command send failed: \(error.localizedDescription, privacy: .public)")
      }
    } else if session.isCompanionAppInstalled {
      // Queued for the next time the phone is awake. Transport commands are
      // near-useless late, but delivering a stale pause beats silently
      // dropping the tap.
      session.transferUserInfo(message)
    } else {
      // No counterpart to queue against. Without this guard the transfer is
      // accepted and then discarded by the daemon with
      // "dropping as pairingIDs no longer match", which is what an unpaired
      // watch simulator produces on every send.
      logger.info("No companion app installed; dropping command")
    }
  }

  // MARK: - Receiving

  private func apply(_ context: PhoneContext) {
    if let upNext = context.upNext { self.upNext = upNext }
    guard let snapshot = context.nowPlaying,
      Self.isNewer(snapshot, than: nowPlaying)
    else { return }
    nowPlaying = snapshot
    // The watch face follows the phone unless the watch is playing its own
    // episode, which publishes its own state (WatchAudioPlayer).
    guard !WatchAudioPlayer.shared.isPlaying else { return }
    let next = WatchComplicationState(
      episodeTitle: snapshot.episodeTitle,
      podcastTitle: snapshot.podcastTitle,
      progress: snapshot.progress,
      isPlaying: snapshot.isPlaying
    )
    let previous = WatchComplicationStore.read()
    guard previous.episodeTitle != next.episodeTitle || previous.isPlaying != next.isPlaying
    else { return }
    WatchComplicationStore.write(next)
    WidgetCenter.shared.reloadTimelines(ofKind: WatchComplicationStore.widgetKind)
  }
}

extension WatchSessionManager {
  /// Contexts queue while the watch sleeps and can land late; applying an
  /// older one would jump the clock backwards, so the newer stamp wins.
  nonisolated static func isNewer(_ snapshot: WidgetPlaybackData, than current: WidgetPlaybackData?) -> Bool {
    guard let current else { return true }
    return snapshot.lastUpdated >= current.lastUpdated
  }
}

/// What one phone context carries, decoded. Either part can be missing.
nonisolated struct PhoneContext: Sendable {
  var nowPlaying: WidgetPlaybackData?
  var upNext: [PlaybackEpisode]?

  /// Decoded off the main actor so only the `Sendable` result crosses the hop —
  /// a `[String: Any]` cannot cross one at all.
  init(_ context: [String: Any]) {
    let decoder = JSONDecoder()
    if let data = context[WatchMessageKey.nowPlaying] as? Data {
      nowPlaying = try? decoder.decode(WidgetPlaybackData.self, from: data)
    }
    if let data = context[WatchMessageKey.upNext] as? Data {
      upNext = try? decoder.decode([PlaybackEpisode].self, from: data)
    }
  }
}

extension WatchSessionManager: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    if let error {
      logger.error("Activation failed: \(error.localizedDescription, privacy: .public)")
      return
    }
    guard activationState == .activated else { return }

    // Only now is the session usable. A context delivered while the app was
    // not running is waiting in `receivedApplicationContext`; decoded here,
    // off the main actor, because the raw [String: Any] cannot cross the hop.
    let context = PhoneContext(session.receivedApplicationContext)
    let reachable = session.isReachable

    Task { @MainActor in
      self.isReachable = reachable
      if context.nowPlaying != nil {
        self.apply(context)
      } else {
        // Never received one. The phone only pushes from its playback funnel,
        // so if nothing has played since this watch app was installed there is
        // nothing waiting — ask, which also wakes the phone app.
        self.send(.requestNowPlaying)
      }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
    let decoded = PhoneContext(context)
    Task { @MainActor in self.apply(decoded) }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    let reachable = session.isReachable
    Task { @MainActor in
      self.isReachable = reachable
      // Cold start out of range: the request sent at activation went nowhere,
      // and the phone has no reason to push on its own. Ask once the link is
      // actually up rather than showing "nothing playing" until playback
      // happens to change on the phone.
      if reachable, self.nowPlaying == nil { self.send(.requestNowPlaying) }
    }
  }
}
