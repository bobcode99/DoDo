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
import ImageIO
import MediaPlayer
import Observation
import OSLog
import WidgetKit

private let logger = Logger(subsystem: "com.jn.PodcastAnalyzer.watch", category: "Playback")

@MainActor
@Observable
final class WatchAudioPlayer {
  static let shared = WatchAudioPlayer()

  private(set) var episode: WatchPlayableEpisode? {
    didSet { if episode?.id != oldValue?.id { loadArtwork() } }
  }
  private(set) var isPlaying = false
  private(set) var currentTime: TimeInterval = 0
  private(set) var duration: TimeInterval = 0

  /// Set when the item itself failed — a dead enclosure URL, a 404, an
  /// unplayable codec. Without it a failed stream looks identical to one that
  /// is merely buffering: the clock sits at 0:00 and the pause button stays
  /// lit forever, because `play()` reports success the moment AVPlayer accepts
  /// the URL rather than when it manages to decode anything.
  private(set) var failureMessage: String?

  var skipBackInterval: TimeInterval = 15
  var skipForwardInterval: TimeInterval = 30

  /// Offered in the system Now Playing "…" menu.
  static let supportedRates: [Float] = [0.8, 1, 1.25, 1.5, 1.75, 2]
  private static let rateKey = "watchPlaybackRate"
  private(set) var rate: Float = {
    let stored = UserDefaults.standard.float(forKey: "watchPlaybackRate")
    return stored > 0 ? stored : 1
  }()

  private var player: AVPlayer?
  /// Bumped by every teardown. A `play(_:)` that resumes from the session
  /// activation await after a newer play or a `stop()` must not build its player.
  private var playRequest = 0
  private var timeObserver: Any?
  /// Set when the caller wants playback to resume from a saved position; the
  /// seek only lands once the item reports a usable duration.
  private var pendingResume: TimeInterval?
  private var statusObservation: NSKeyValueObservation?
  private var timeControlObservation: NSKeyValueObservation?
  private var endObserverTask: Task<Void, Never>?
  /// The system Now Playing screen shows only what nowPlayingInfo carries —
  /// without this the watch's own playback had no picture at all.
  private var artwork: MPMediaItemArtwork?
  private var artworkTask: Task<Void, Never>?
  /// Position last written to the progress store, so playback checkpoints every
  /// `checkpointInterval` instead of only on pause — a watch app is suspended
  /// or killed mid-episode far more often than a phone app.
  private var lastPersistedTime: TimeInterval = 0
  static let checkpointInterval: TimeInterval = 30

  private static let lastEpisodeKey = "watchLastEpisode"
  private static let lastPositionKey = "watchLastPosition"

  private init() {
    configureRemoteCommands()
    restoreLastEpisode()
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
    let request = playRequest

    // Up Next and Shows hand over the remote URL; a copy already on the watch
    // must still win, or a downloaded episode streams (or fails off-network).
    var episode = episode
    if episode.localPath == nil,
      let download = WatchDownloadManager.shared.downloadedModel(for: episode.progressKey)
    {
      episode.localPath = download.localPath
    }

    guard let url = episode.playbackURL else {
      logger.error("No playable URL for \(episode.title, privacy: .public)")
      self.episode = episode
      failureMessage = String(localized: "This episode has no playable audio.")
      return
    }

    self.episode = episode
    failureMessage = nil
    currentTime = position
    lastPersistedTime = position
    duration = 0
    pendingResume = position > 0 ? position : nil
    saveLastEpisode()

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
    // A newer play() or a stop() tore down while this call waited; the
    // player it would build now has nothing to stop it, so build none.
    guard request == playRequest else { return }

    let item = AVPlayerItem(url: url)
    // KVO rather than a check inside the periodic observer: a failed item never
    // advances its clock, so that observer would never fire to notice.
    statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      guard item.status == .failed else { return }
      let message = item.error?.localizedDescription
      Task { @MainActor in self?.handleItemFailure(message) }
    }

    endObserverTask = Task { [weak self] in
      for await _ in NotificationCenter.default.notifications(
        named: AVPlayerItem.didPlayToEndTimeNotification, object: item)
      {
        self?.handleItemEnded()
      }
    }

    let player = AVPlayer(playerItem: item)
    // play() starts at defaultRate, so the chosen speed survives pause/resume.
    player.defaultRate = rate
    self.player = player
    observeTime(on: player)
    // The system pauses the player itself — a call, Siri, headphones taken
    // off, the item ending. Mirror that, or the UI keeps showing Pause over
    // silence.
    timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
      guard player.timeControlStatus == .paused else { return }
      Task { @MainActor in self?.systemDidPause() }
    }
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
    guard player != nil else {
      // Restored after a relaunch, or torn down after a failure: build the
      // player again from where it stopped.
      if let episode {
        Task { await play(episode, resumingAt: currentTime) }
      }
      return
    }
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

  func setRate(_ newRate: Float) {
    rate = newRate
    UserDefaults.standard.set(newRate, forKey: Self.rateKey)
    player?.defaultRate = newRate
    if isPlaying { player?.rate = newRate }
    updateNowPlayingInfo()
  }

  func skipForward() { seek(to: currentTime + skipForwardInterval) }
  func skipBackward() { seek(to: currentTime - skipBackInterval) }

  /// Call when leaving the player so a half-listened episode is not lost.
  func checkpoint() { persistProgress() }

  /// Playback moved to the iPhone. Clearing the episode empties this watch's
  /// Now Playing, so the system player switches to showing the phone's.
  func stop() {
    teardown()
    episode = nil
    UserDefaults.standard.removeObject(forKey: Self.lastEpisodeKey)
    updateNowPlayingInfo()
  }

  // MARK: - Time

  private func observeTime(on player: AVPlayer) {
    // 1s rather than the phone's 0.25s: the watch only draws a coarse scrubber
    // and a clock, and each tick is a main-actor hop plus a redraw.
    let interval = CMTime(seconds: 1, preferredTimescale: 600)
    timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      MainActor.assumeIsolated {
        guard let self else { return }
        // NaN until the item is ready, and a NaN here propagates into
        // `progress` and then into a ProgressView, which draws nothing and
        // logs for every tick afterwards.
        if time.seconds.isFinite { self.currentTime = time.seconds }
        if abs(self.currentTime - self.lastPersistedTime) >= Self.checkpointInterval {
          self.persistProgress()
        }

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

  /// Stops the transport and tells the user, instead of leaving the UI in a
  /// permanent "playing" state that never moves.
  private func handleItemFailure(_ message: String?) {
    logger.error("Playback item failed: \(message ?? "unknown", privacy: .public)")
    // Drop the dead player so tapping the episode again builds a new one;
    // resume() on a failed item does nothing.
    teardown()
    failureMessage = message ?? String(localized: "Couldn't play this episode.")
    updateNowPlayingInfo()
  }

  /// The episode played to the end: record it as finished and park at 0:00 so
  /// Play starts it again instead of sitting on the last frame.
  private func handleItemEnded() {
    if duration > 0 { currentTime = duration }
    persistProgress()
    isPlaying = false
    currentTime = 0
    lastPersistedTime = 0
    player?.seek(to: .zero)
    UserDefaults.standard.set(0, forKey: Self.lastPositionKey)
    updateNowPlayingInfo()
  }

  /// Something other than our own pause() stopped playback.
  private func systemDidPause() {
    guard isPlaying, player?.timeControlStatus == .paused else { return }
    isPlaying = false
    persistProgress()
    updateNowPlayingInfo()
  }

  private func teardown() {
    playRequest += 1
    persistProgress()
    endObserverTask?.cancel()
    endObserverTask = nil
    timeControlObservation?.invalidate()
    timeControlObservation = nil
    statusObservation?.invalidate()
    statusObservation = nil
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
    lastPersistedTime = currentTime
    UserDefaults.standard.set(currentTime, forKey: Self.lastPositionKey)
    WatchProgressStore.shared.record(
      id: episode.progressKey,
      position: currentTime,
      duration: duration
    )
  }

  // MARK: - Last episode

  /// Remembered across launches so Now Playing opens on what was playing, with
  /// Play ready, rather than "Pick an episode".
  private func saveLastEpisode() {
    guard let episode, let data = try? JSONEncoder().encode(episode) else { return }
    UserDefaults.standard.set(data, forKey: Self.lastEpisodeKey)
  }

  private func restoreLastEpisode() {
    guard let data = UserDefaults.standard.data(forKey: Self.lastEpisodeKey),
      let saved = try? JSONDecoder().decode(WatchPlayableEpisode.self, from: data)
    else { return }
    episode = saved
    currentTime = UserDefaults.standard.double(forKey: Self.lastPositionKey)
    lastPersistedTime = currentTime
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
    // What a headphone button sends; play/pause alone leave it unhandled.
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.togglePlayPause() }
      return .success
    }
    center.changePlaybackRateCommand.supportedPlaybackRates = Self.supportedRates.map { NSNumber(value: $0) }
    center.changePlaybackRateCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
      let rate = event.playbackRate
      Task { @MainActor in self?.setRate(rate) }
      return .success
    }
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
      let position = event.positionTime
      Task { @MainActor in self?.seek(to: position) }
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
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: episode.title,
      MPMediaItemPropertyArtist: episode.podcastTitle,
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
    ]
    info[MPMediaItemPropertyArtwork] = artwork
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func loadArtwork() {
    artworkTask?.cancel()
    artwork = nil
    guard let string = episode?.imageURL, let url = URL(string: string) else { return }
    artworkTask = Task {
      guard let image = await Self.thumbnail(from: url), !Task.isCancelled else { return }
      artwork = Self.makeArtwork(image)
      updateNowPlayingInfo()
    }
  }

  /// Feed art is often 3000 px square — about 36 MB decoded, which a watch
  /// cannot spare. 512 px covers the largest watch screen. Cache first, like
  /// WatchArtwork: offline playback of a download is the common case here.
  private nonisolated static func thumbnail(from url: URL) async -> UIImage? {
    let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
    guard let (data, _) = try? await URLSession.shared.data(for: request),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 512,
        ] as CFDictionary)
    else { return nil }
    return UIImage(cgImage: image)
  }

  /// Nonisolated so the handler isn't main-actor-bound: the system calls it on
  /// its own queue, and a main-actor closure traps there under Swift 6.
  private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: image.size) { _ in image }
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
