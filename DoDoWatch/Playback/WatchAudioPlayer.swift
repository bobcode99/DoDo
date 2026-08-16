//
//  WatchAudioPlayer.swift
//  DoDoWatch
//
//  The watch plays audio itself rather than driving the phone. Deliberately
//  its own small player instead of a port of EnhancedAudioManager: that class
//  is 1619 lines wired to captions, downloads and the widget's App Group, and
//  Pocket Casts' equivalent decision — compiling their 2400-line PlaybackManager
//  into the watch behind ~20 `#if os(watchOS)` branches — is the part of their
//  setup most likely to break when iOS playback changes.
//

import AVFoundation
import Foundation
import MediaPlayer
import Observation
import OSLog
import WidgetKit

private let logger = Logger(subsystem: "com.jn.PodcastAnalyzer.watch", category: "Playback")

@MainActor
@Observable
final class WatchAudioPlayer {
  static let shared = WatchAudioPlayer()

  private(set) var episode: WatchPlayableEpisode?
  private(set) var isPlaying = false
  private(set) var currentTime: TimeInterval = 0
  private(set) var duration: TimeInterval = 0

  var skipBackInterval: TimeInterval = 15
  var skipForwardInterval: TimeInterval = 30

  private var player: AVPlayer?
  private var timeObserver: Any?
  /// Set when the caller wants playback to resume from a saved position; the
  /// seek only lands once the item reports a usable duration.
  private var pendingResume: TimeInterval?

  private init() {
    configureRemoteCommands()
  }

  var progress: Double {
    guard duration > 0 else { return 0 }
    return min(currentTime / duration, 1)
  }

  // MARK: - Transport

  func play(_ episode: WatchPlayableEpisode, resumingAt position: TimeInterval = 0) async {
    if self.episode?.id == episode.id, player != nil {
      resume()
      return
    }

    teardown()

    guard let url = episode.playbackURL else {
      logger.error("No playable URL for \(episode.title, privacy: .public)")
      return
    }

    self.episode = episode
    currentTime = position
    duration = 0
    pendingResume = position > 0 ? position : nil

    // watchOS wants the session active before the player starts, and its
    // activation is async — unlike iOS, where setActive(_:) is synchronous.
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
      try await session.activate()
    } catch {
      // Non-fatal: playback through the built-in speaker can still work, and
      // failing loudly here would block an otherwise usable session.
      logger.error("Audio session activation failed: \(error.localizedDescription, privacy: .public)")
    }

    let player = AVPlayer(url: url)
    self.player = player
    observeTime(on: player)
    player.play()
    isPlaying = true
    updateNowPlayingInfo()
  }

  func togglePlayPause() {
    isPlaying ? pause() : resume()
  }

  func pause() {
    player?.pause()
    isPlaying = false
    updateNowPlayingInfo()
    persistProgress()
  }

  func resume() {
    guard player != nil else { return }
    player?.play()
    isPlaying = true
    updateNowPlayingInfo()
  }

  func seek(to time: TimeInterval) {
    guard let player else { return }
    let clamped = max(0, duration > 0 ? min(time, duration) : time)
    player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    currentTime = clamped
    updateNowPlayingInfo()
    persistProgress()
  }

  func skipForward() { seek(to: currentTime + skipForwardInterval) }
  func skipBackward() { seek(to: currentTime - skipBackInterval) }

  /// Call when leaving the player so a half-listened episode is not lost.
  func checkpoint() { persistProgress() }

  // MARK: - Time

  private func observeTime(on player: AVPlayer) {
    // 1s rather than the phone's 0.25s: the watch only draws a coarse scrubber
    // and a clock, and each tick is a main-actor hop plus a redraw.
    let interval = CMTime(seconds: 1, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.currentTime = time.seconds

        if let itemDuration = player.currentItem?.duration.seconds,
          itemDuration.isFinite, itemDuration > 0
        {
          self.duration = itemDuration
          if let resume = self.pendingResume {
            self.pendingResume = nil
            self.seek(to: resume)
          }
        }
      }
    }
  }

  private func teardown() {
    persistProgress()
    if let timeObserver { player?.removeTimeObserver(timeObserver) }
    timeObserver = nil
    player?.pause()
    player = nil
    isPlaying = false
  }

  // MARK: - Progress

  /// Writes into the CloudKit-mirrored row, stamping `updatedAt` and
  /// `deviceName` so the phone's PlaybackProgressSyncCoordinator can resolve
  /// last-writer-wins without any watch-specific merge logic.
  private func persistProgress() {
    guard let episode, currentTime > 0 else { return }
    WatchProgressStore.shared.record(
      id: episode.progressKey,
      position: currentTime,
      duration: duration
    )
  }

  // MARK: - Now Playing

  private func configureRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()

    // Hopped onto the main actor rather than asserted onto it: the thread these
    // handlers run on is not documented, so `MainActor.assumeIsolated` would be
    // a crash waiting for a system that decides to call us elsewhere.
    center.playCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.resume() }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.pause() }
      return .success
    }
    center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardInterval)]
    center.skipForwardCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.skipForward() }
      return .success
    }
    center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackInterval)]
    center.skipBackwardCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.skipBackward() }
      return .success
    }
  }

  private func updateNowPlayingInfo() {
    publishComplicationState()
    guard let episode else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: episode.title,
      MPMediaItemPropertyArtist: episode.podcastTitle,
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
    ]
  }

  /// Pushed to the watch face. Only on episode/play-state changes rather than
  /// every tick — complication reloads are a scarce budget on watchOS, and the
  /// progress bar at this size cannot show a second of movement anyway.
  private func publishComplicationState() {
    let next =
      episode.map {
        WatchComplicationState(
          episodeTitle: $0.title,
          podcastTitle: $0.podcastTitle,
          progress: progress,
          isPlaying: isPlaying
        )
      } ?? .empty

    let previous = WatchComplicationStore.read()
    guard previous.episodeTitle != next.episodeTitle || previous.isPlaying != next.isPlaying
    else { return }

    WatchComplicationStore.write(next)
    WidgetCenter.shared.reloadTimelines(ofKind: WatchComplicationStore.widgetKind)
  }
}
