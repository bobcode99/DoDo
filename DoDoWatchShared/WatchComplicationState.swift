//
//  WatchComplicationState.swift
//  DoDoWatch / DoDoWatchWidget
//
//  What the watch face shows. Kept to four primitives in App Group
//  UserDefaults rather than reusing `WidgetPlaybackData`: the widget extension
//  is a separate process, and sharing that type would mean compiling all of
//  SharedCore — SwiftData models, FeedKit — into a target that renders one
//  line of text.
//
//  App Groups do work here, unlike phone↔watch: both processes are on the
//  same device.
//

import Foundation

struct WatchComplicationState: Equatable, Sendable {
  var episodeTitle: String
  var podcastTitle: String
  var progress: Double
  var isPlaying: Bool

  static let empty = WatchComplicationState(
    episodeTitle: "", podcastTitle: "", progress: 0, isPlaying: false)

  var hasEpisode: Bool { !episodeTitle.isEmpty }
}

enum WatchComplicationStore {
  static let appGroupIdentifier = "group.com.jn.PodcastAnalyzer"

  /// Widget kind, shared so the app can reload exactly this timeline.
  static let widgetKind = "DoDoNowPlayingComplication"

  private enum Key {
    static let episodeTitle = "watch.nowPlaying.episodeTitle"
    static let podcastTitle = "watch.nowPlaying.podcastTitle"
    static let progress = "watch.nowPlaying.progress"
    static let isPlaying = "watch.nowPlaying.isPlaying"
  }

  private static var defaults: UserDefaults? {
    UserDefaults(suiteName: appGroupIdentifier)
  }

  static func read() -> WatchComplicationState {
    guard let defaults else { return .empty }
    return WatchComplicationState(
      episodeTitle: defaults.string(forKey: Key.episodeTitle) ?? "",
      podcastTitle: defaults.string(forKey: Key.podcastTitle) ?? "",
      progress: defaults.double(forKey: Key.progress),
      isPlaying: defaults.bool(forKey: Key.isPlaying)
    )
  }

  static func write(_ state: WatchComplicationState) {
    guard let defaults else { return }
    defaults.set(state.episodeTitle, forKey: Key.episodeTitle)
    defaults.set(state.podcastTitle, forKey: Key.podcastTitle)
    defaults.set(state.progress, forKey: Key.progress)
    defaults.set(state.isPlaying, forKey: Key.isPlaying)
  }
}
