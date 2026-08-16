//
//  WatchCommand.swift
//  PodcastAnalyzer
//
//  What the watch can ask the phone to do when the user has picked the phone
//  as the play source. Deliberately tiny: Pocket Casts carries ~30 message
//  types (podcasts/WatchConstants.swift) because their watch also mutates
//  library state over the wire. Ours does not — subscriptions, progress and
//  Up Next all travel through CloudKit — so this covers transport only.
//

import Foundation

nonisolated enum WatchCommand: Codable, Sendable, Equatable {
  case togglePlayPause
  case skipForward
  case skipBackward
  case seek(to: TimeInterval)
  case setRate(Float)

  /// "Send me the current state." The phone only pushes from its playback
  /// funnel, so a watch installed before anything played has never received a
  /// context at all. Sending this wakes the phone app, which answers with one.
  /// Pocket Casts does the same from `SessionManager.setup()` (`:18-23`).
  case requestNowPlaying
}

/// Keys for the `[String: Any]` dictionaries WatchConnectivity actually moves.
/// Both sides encode their payload to JSON and post it under one key, rather
/// than spreading fields across the dictionary — it keeps the wire format in
/// step with the Codable types automatically.
nonisolated enum WatchMessageKey {
  /// A JSON-encoded `WatchCommand`, watch → phone.
  static let command = "command"
  /// A JSON-encoded `WidgetPlaybackData`, phone → watch.
  static let nowPlaying = "nowPlaying"
}
