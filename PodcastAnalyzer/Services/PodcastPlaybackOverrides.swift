//
//  PodcastPlaybackOverrides.swift
//  PodcastAnalyzer
//
//  Per-show playback settings, read out of SwiftData and handed to
//  `EnhancedAudioManager` as a plain value so the audio layer needs no store.
//

import Foundation

struct PodcastPlaybackOverrides: Sendable, Equatable {
  /// 0 means "no override" — fall back to the global default speed.
  let speed: Float
  /// Seconds to skip at the start of an episode. 0 = none.
  let skipIntro: TimeInterval
  /// Seconds before the real end to treat an episode as finished. 0 = none.
  let skipOutro: TimeInterval

  static let none = PodcastPlaybackOverrides(speed: 0, skipIntro: 0, skipOutro: 0)
}
