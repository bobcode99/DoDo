//
//  PlaySource.swift
//  DoDoWatch
//
//  Whether the transport controls drive this watch or the paired iPhone.
//
//  Lifted from Pocket Casts, whose whole watch app hangs off the same two-case
//  choice (`UI/SourceManager.swift`). Theirs gates the watch option behind a
//  Plus subscription; ours is always available, because standalone playback
//  costs us nothing extra — the data is already on the watch.
//

import Foundation
import Observation

enum PlaySource: Int, CaseIterable, Identifiable {
  case watch = 0
  case phone = 1

  var id: Int { rawValue }

  var title: String {
    switch self {
    case .watch: "Watch"
    case .phone: "iPhone"
    }
  }

  var systemImage: String {
    switch self {
    case .watch: "applewatch"
    case .phone: "iphone"
    }
  }
}

@MainActor
@Observable
final class SourceManager {
  static let shared = SourceManager()

  private static let defaultsKey = "playSource"

  var selected: PlaySource {
    didSet { UserDefaults.standard.set(selected.rawValue, forKey: Self.defaultsKey) }
  }

  private init() {
    let stored = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Int
    // Defaults to the watch: an app that does nothing without the phone in
    // range is a worse first run than one that streams.
    selected = stored.flatMap(PlaySource.init(rawValue:)) ?? .watch
  }
}
