//
//  EnhancedAudioManager.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

//
//  EnhancedAudioManager.swift
//  PodcastAnalyzer
//
//  Manages audio playback with background support, Now Playing info, and transcript tracking
//

import AVFoundation
import CoreFoundation
import Foundation
import MediaPlayer
import OSLog
import WidgetKit

#if os(iOS)
import UIKit
#else
import AppKit
#endif

// MARK: - Playback State Notification
extension Notification.Name {
  static let playbackPositionDidUpdate = Notification.Name("playbackPositionDidUpdate")
  /// Posted when the audio manager refuses to start playback. userInfo["message"]
  /// holds a user-facing string the UI should surface (toast/alert). Currently
  /// fires when a remote URL is requested with no network connection and no
  /// local copy is available.
  static let audioPlaybackUnavailable = Notification.Name("audioPlaybackUnavailable")
}

struct PlaybackPositionUpdate: Sendable {
  let episodeTitle: String
  let podcastTitle: String
  let position: TimeInterval
  let duration: TimeInterval
  let audioURL: String  // Added: needed to create new models
}

// MARK: - Sleep Timer Options

enum SleepTimerOption: Equatable, CaseIterable {
  case off
  case endOfEpisode
  case minutes5
  case minutes10
  case minutes15
  case minutes30
  case minutes45
  case hour1

  var displayName: String {
    switch self {
    case .off: return "Off"
    case .endOfEpisode: return "End of Episode"
    case .minutes5: return "5 Minutes"
    case .minutes10: return "10 Minutes"
    case .minutes15: return "15 Minutes"
    case .minutes30: return "30 Minutes"
    case .minutes45: return "45 Minutes"
    case .hour1: return "1 Hour"
    }
  }

  var duration: TimeInterval? {
    switch self {
    case .off: return nil
    case .endOfEpisode: return nil  // Special case - handled separately
    case .minutes5: return 5 * 60
    case .minutes10: return 10 * 60
    case .minutes15: return 15 * 60
    case .minutes30: return 30 * 60
    case .minutes45: return 45 * 60
    case .hour1: return 60 * 60
    }
  }

  var systemImage: String {
    switch self {
    case .off: return "moon.zzz"
    case .endOfEpisode: return "stop.circle"
    default: return "timer"
    }
  }
}

@MainActor @Observable
class EnhancedAudioManager: NSObject {
  static let shared = EnhancedAudioManager()

  var player: AVPlayer?
  var isPlaying: Bool = false
  var currentEpisode: PlaybackEpisode?
  var currentTime: TimeInterval = 0
  var duration: TimeInterval = 0
  var playbackRate: Float = 1.0
  var volume: Float = 1.0

  var currentCaption: String = ""
  var captionSegments: [CaptionSegment] = []

  // Queue management
  var queue: [PlaybackEpisode] = []
  var hasRestoredLastEpisode: Bool = false
  private let maxQueueSize = 50

  // Auto-play candidates (unplayed episodes that can be randomly selected)
  var autoPlayCandidates: [PlaybackEpisode] = []

  // Sleep timer
  var sleepTimerOption: SleepTimerOption = .off
  var sleepTimerRemaining: TimeInterval = 0
  private var sleepTimerTask: Task<Void, Never>?

  // Audio interruption handling - track if we should resume after interruption ends
  private var wasPlayingBeforeInterruption: Bool = false

  // True between handlePlaybackEnded (no-next branch) and the seek-to-zero
  // completion. Stops the periodic time observer from overwriting the
  // currentTime we just reset to 0 with a stale player position.
  private var suppressTimeObserverUntilSeekLands = false

  // Generation token incremented on every user-initiated playback state change
  // (pause/play/stop/seek/play(...)). The delayed interruption-resume retry
  // captures the token at start and bails if it changed, so a manual pause
  // during the retry window can't be overridden by the resume retry firing.
  private var playbackStateGeneration: UInt64 = 0

  // Track last values pushed to widget to avoid burning WidgetKit reload budget
  private var lastWidgetAudioURL: String?
  private var lastWidgetIsPlaying: Bool?

  private var timeObserver: Any?
  // Task-based observers for Swift 6 concurrency
  private var interruptionTask: Task<Void, Never>?
  private var interruptionResumeTask: Task<Void, Never>?
  private var playerEndedTask: Task<Void, Never>?
  private var playerStalledTask: Task<Void, Never>?
  private var artworkFetchTask: Task<Void, Never>?
  private var captionLoadTask: Task<Void, Never>?
  private var durationLoadTask: Task<Void, Never>?
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "AudioManager")

  // Use Unit Separator (U+001F) as delimiter - same as EpisodeDownloadModel
  private static let episodeKeyDelimiter = "\u{1F}"

  // Pre-compiled SRT regex (compiled once, reused for every caption parse)
  private static let srtRegex: NSRegularExpression? = {
    let entryPattern =
      #"(?:^|\n)(\d+)\n(\d{2}:\d{2}:\d{2}[,\.]\d{3})\s*-->\s*(\d{2}:\d{2}:\d{2}[,\.]\d{3})\n"#
    return try? NSRegularExpression(pattern: entryPattern, options: [])
  }()

  private enum Keys {
    static let lastEpisodeTitle = "lastEpisodeTitle"
    static let lastPodcastTitle = "lastPodcastTitle"
    static let lastPlaybackTime = "lastPlaybackTime"
    static let lastDuration = "lastDuration"
    static let lastAudioURL = "lastAudioURL"
    static let playbackRate = "playbackRate"
    static let lastImageURL = "lastImageURL"
    static let defaultPlaybackSpeed = "defaultPlaybackSpeed"
    static let autoPlayNextEpisode = "autoPlayNextEpisode"
    static let lastEpisodeDescription = "lastEpisodeDescription"
    static let lastEpisodePubDate = "lastEpisodePubDate"
    static let lastEpisodeGuid = "lastEpisodeGuid"
  }

  override private init() {
    super.init()
    setupAudioSession()
    setupRemoteControls()
    setupInterruptionObserver()
    #if os(iOS)
    // Critical for remote commands on iOS!
    UIApplication.shared.beginReceivingRemoteControlEvents()
    #endif
    loadPlaybackRate()
    registerWidgetNotifications()
  }

  /// Register a Darwin notification observer so the widget can signal a play/pause
  /// toggle without bringing the app to the foreground.
  private func registerWidgetNotifications() {
    #if os(iOS)
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      nil,
      { _, _, _, _, _ in
        Task { @MainActor in
          EnhancedAudioManager.shared.checkWidgetTogglePlayback()
        }
      },
      "com.jn.PodcastAnalyzer.togglePlayback" as CFString,
      nil,
      .deliverImmediately
    )
    #endif
  }

  private func setupAudioSession() {
    #if os(iOS)
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio, options: [])
      // Don't activate session here - only activate when actually playing
      logger.info("Audio session configured (will activate when playing)")
    } catch {
      logger.error("Audio session setup failed: \(error.localizedDescription, privacy: .public)")
    }
    #else
    // macOS doesn't require AVAudioSession configuration
    logger.info("Audio manager initialized for macOS")
    #endif
  }

  private func activateAudioSession() {
    #if os(iOS)
    do {
      try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
      logger.info("Audio session activated")
    } catch {
      logger.error("Failed to activate audio session: \(error.localizedDescription, privacy: .public)")
    }
    #endif
  }

  private func deactivateAudioSession() {
    #if os(iOS)
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      logger.info("Audio session deactivated - other apps can now play")
    } catch {
      logger.error("Failed to deactivate audio session: \(error.localizedDescription, privacy: .public)")
    }
    #endif
  }

  private func setupInterruptionObserver() {
    #if os(iOS)
    // Use Task-based async sequence for Swift 6 concurrency
    interruptionTask = Task { @MainActor [weak self] in
      for await notification in NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification) {
        self?.handleAudioInterruption(notification)
      }
    }
    logger.info("Audio interruption observer configured")
    #endif
  }

private func handleAudioInterruption(_ notification: Notification) {
    #if os(iOS)
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }

    logger.info("Handling audio interruption: type=\(type.rawValue, privacy: .public)")


    switch type {
    case .began:
        // 1. Mark our state BEFORE we call pause()
        wasPlayingBeforeInterruption = isPlaying
        
        if isPlaying {
            // We use a local pause here to stop the player
            // but we don't necessarily want to treat this as a "user-stop"
            player?.pause()
            isPlaying = false
            updateNowPlayingPlaybackRate()
            logger.info("Interruption began: Audio paused")
        }

    case .ended:
        // 2. Determine if we SHOULD resume
        // We check the system hint AND our manual flag
        var shouldResume = false
        if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                shouldResume = true
            }
        }
        
        // If system says yes OR our manual state says we were playing
        let finalDecisionToResume = shouldResume || wasPlayingBeforeInterruption
        
        if finalDecisionToResume {
            // 3. Mandatory Session Reactivation
            do {
                try AVAudioSession.sharedInstance().setActive(true)

                // 4. Delayed Resume with retry
                // Audio hardware needs a moment to switch back from the other app
                interruptionResumeTask?.cancel()
                interruptionResumeTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(0.8))
                    guard let self, !Task.isCancelled else { return }
                    self.resume()
                    self.wasPlayingBeforeInterruption = false
                    // Snapshot the generation token AFTER our resume() so any
                    // user-initiated pause/play during the 0.5s verification
                    // window bumps the token and aborts the retry.
                    let tokenAtRetryStart = self.playbackStateGeneration
                    try? await Task.sleep(for: .seconds(0.5))
                    guard !Task.isCancelled,
                          self.playbackStateGeneration == tokenAtRetryStart
                    else {
                        self.logger.info(
                            "Interruption retry aborted: user changed playback state during window")
                        return
                    }
                    if !self.isPlaying, self.player?.rate == 0 {
                        self.logger.warning("Interruption resume failed, retrying once")
                        self.resume()
                    } else {
                        self.logger.info("Interruption ended: Audio resumed successfully")
                    }
                }
            } catch {
                logger.error("Failed to reactivate session after interruption: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            wasPlayingBeforeInterruption = false
        }

    @unknown default:
        break
    }
    #endif
}

  private func setupRemoteControls() {
    let commandCenter = MPRemoteCommandCenter.shared()

    // Remove any existing targets before adding to prevent handler accumulation
    commandCenter.playCommand.removeTarget(nil)
    commandCenter.pauseCommand.removeTarget(nil)
    commandCenter.skipForwardCommand.removeTarget(nil)
    commandCenter.skipBackwardCommand.removeTarget(nil)
    commandCenter.nextTrackCommand.removeTarget(nil)
    commandCenter.previousTrackCommand.removeTarget(nil)
    commandCenter.changePlaybackPositionCommand.removeTarget(nil)

    // Remote command handlers run on arbitrary queues, so dispatch to MainActor
    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.resume() }
      return .success
    }

    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.pause() }
      return .success
    }

    commandCenter.skipForwardCommand.isEnabled = true
    commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardInterval)]
    commandCenter.skipForwardCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.skipForward() }
      return .success
    }

    commandCenter.skipBackwardCommand.isEnabled = true
    commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackwardInterval)]
    commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.skipBackward() }
      return .success
    }

    // AirPods physical-button gestures:
    //   • Double-press / double-tap → nextTrackCommand
    //   • Triple-press / triple-tap → previousTrackCommand
    // iOS consumes these events and dispatches ONLY to the next/previous-track
    // handlers — they don't fall through to skipForward/skipBackward — so
    // without registering here, AirPods clicks silently do nothing. Route them
    // through our skip handlers so the gestures behave the same way as the
    // lock-screen skip buttons.
    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.nextTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.skipForward() }
      return .success
    }

    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.skipBackward() }
      return .success
    }

    commandCenter.changePlaybackPositionCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      let position = event.positionTime
      Task { @MainActor in self?.seek(to: position) }
      return .success
    }
  }

  // MARK: - Play
  func play(
    episode: PlaybackEpisode, audioURL: String, startTime: TimeInterval = 0,
    imageURL: String? = nil, useDefaultSpeed: Bool = false
  ) {
    guard let initialURL = URL(string: audioURL) else { return }

    if currentEpisode?.id == episode.id, player != nil {
      if isPlaying { pause() } else { resume() }
      return
    }

    // Starting a new episode invalidates any pending interruption-resume retry
    // for the previous one.
    playbackStateGeneration &+= 1

    // Resolve the URL we will actually play. If the caller passed a remote URL
    // but the episode is already downloaded, prefer the local file. Only block
    // on "no network" if NWPathMonitor has actually reported back at least
    // once and confirmed we're offline — otherwise the default `isConnected =
    // false` would falsely refuse playback during the ~200ms window between
    // NetworkMonitor init and the first path update.
    let url: URL
    if initialURL.isFileURL {
      url = initialURL
    } else if case .downloaded(let localPath) = DownloadManager.shared
      .getDownloadState(episodeTitle: episode.title, podcastTitle: episode.podcastTitle),
      FileManager.default.fileExists(atPath: localPath)
    {
      url = URL(fileURLWithPath: localPath)
      logger.info("Using downloaded copy for \(episode.title)")
    } else {
      let monitor = NetworkMonitor.shared
      if monitor.hasReceivedFirstUpdate && !monitor.isConnected {
        let message =
          "Can't reach the internet right now. Download \"\(episode.title)\" while you're on Wi-Fi to listen offline."
        logger.warning(
          "Refusing playback: NWPathMonitor reports offline and no local copy for \(episode.title)")
        NotificationCenter.default.post(
          name: .audioPlaybackUnavailable,
          object: nil,
          userInfo: ["message": message, "episodeTitle": episode.title])
        return
      }
      url = initialURL
    }

    cleanup()

    // Activate audio session now that we're about to play
    activateAudioSession()

    // Use cached duration from episode metadata if available
    // This provides immediate feedback instead of showing 0:00
    if let episodeDuration = episode.duration, episodeDuration > 0 {
      duration = TimeInterval(episodeDuration)
    } else {
      duration = 0
    }
    currentTime = startTime > 0 ? startTime : 0

    // Apply default speed from settings for new episodes
    if useDefaultSpeed {
      let defaultSpeed = UserDefaults.standard.float(forKey: Keys.defaultPlaybackSpeed)
      if defaultSpeed > 0 {
        playbackRate = defaultSpeed
        UserDefaults.standard.set(defaultSpeed, forKey: Keys.playbackRate)
      }
    }

    let playerItem = AVPlayerItem(url: url)
    player = AVPlayer(playerItem: playerItem)
    player?.volume = volume
    currentEpisode = episode

    // Update Now Playing info with cached duration (will be refined when AVPlayer reports actual duration)
    updateNowPlayingInfo(imageURL: imageURL ?? episode.imageURL)

    // Replace the metadata-seeded duration with the real asset length ASAP,
    // before the first playing tick of the periodic observer lands.
    loadRealDuration(from: url)

    if startTime > 0 {
      player?.seek(
        to: CMTime(seconds: startTime, preferredTimescale: 600),
        toleranceBefore: .zero,
        toleranceAfter: .zero
      )
    }

    setupTimeObserver()
    setupPlayerObservers(playerItem: playerItem)

    player?.play()
    player?.rate = playbackRate
    isPlaying = true

    savePlaybackState(imageURL: imageURL ?? episode.imageURL)
    loadCaptions(episode: episode)
    updateWidgetPlaybackData()
  }

  // MARK: - Controls – always update Now Playing
  func pause() {
    playbackStateGeneration &+= 1
    player?.pause()
    isPlaying = false
    updateNowPlayingPlaybackRate()
    savePlaybackState()
    postPlaybackPositionUpdate()
    updateWidgetPlaybackData()
  }

  func resume() {
    playbackStateGeneration &+= 1
    // If we have a restored episode but no player, start playback
    if player == nil, let episode = currentEpisode {
      play(
        episode: episode,
        audioURL: episode.audioURL,
        startTime: currentTime,
        imageURL: episode.imageURL,
        useDefaultSpeed: false
      )
      return
    }

    // Ensure audio session is active when resuming
    activateAudioSession()

    // If the player is parked at the end of the item, AVPlayer.play() is a
    // no-op. Seek to zero first so Replay actually starts over.
    if let item = player?.currentItem {
      let itemTime = item.currentTime().seconds
      let itemDuration = item.duration.seconds
      if itemTime.isFinite, itemDuration.isFinite, itemDuration > 0,
        itemTime >= itemDuration - 0.5
      {
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = 0
      }
    }

    player?.play()
    player?.rate = playbackRate
    isPlaying = true
    updateNowPlayingPlaybackRate()
    savePlaybackState()
  }

  func stop() {
    playbackStateGeneration &+= 1
    cleanup()
    currentEpisode = nil
    currentTime = 0
    duration = 0
    isPlaying = false
    currentCaption = ""
    captionSegments = []
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil

    // Deactivate audio session so other apps can play
    deactivateAudioSession()

    // Clear widget data
    clearWidgetData()

    logger.info("Playback stopped and audio session deactivated")
  }

  func seek(to time: TimeInterval) {
    let beforeTime = currentTime
    logger.info("seek(to:) requested target=\(String(format: "%.3f", time))s currentBefore=\(String(format: "%.3f", beforeTime))s")
    let cmTime = CMTime(seconds: time, preferredTimescale: 600)
    // Use zero tolerance so the playhead lands exactly at the requested time.
    // Without this, AVPlayer defaults to kCMTimePositiveInfinity tolerances and
    // may snap to a nearby keyframe — causing transcript taps to jump to the
    // wrong timestamp.
    player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
      // Dispatch to main actor since completion handler runs on arbitrary queue
      Task { @MainActor in
        guard let self else { return }
        let landed = self.player?.currentTime().seconds ?? .nan
        self.logger.info(
          "seek(to:) completion target=\(String(format: "%.3f", time))s landed=\(String(format: "%.3f", landed))s drift=\(String(format: "%.3f", landed - time))s finished=\(finished)"
        )
        // Update currentTime immediately so observers (e.g. TranscriptContentView
        // polling timer) see the seeked position rather than the stale value that
        // the periodic time observer hasn't flushed yet.
        self.currentTime = time
        self.updateNowPlayingCurrentTime()
        self.savePlaybackState()
        self.postPlaybackPositionUpdate()
      }
    }
  }

  var skipForwardInterval: TimeInterval {
    let saved = UserDefaults.standard.integer(forKey: "skipForwardInterval")
    return TimeInterval(saved > 0 ? saved : 30)
  }

  var skipBackwardInterval: TimeInterval {
    let saved = UserDefaults.standard.integer(forKey: "skipBackwardInterval")
    return TimeInterval(saved > 0 ? saved : 15)
  }

  func skipForward(seconds: TimeInterval? = nil) {
    let s = seconds ?? skipForwardInterval
    let newTime = min(currentTime + s, duration)
    seek(to: newTime)
  }

  func skipBackward(seconds: TimeInterval? = nil) {
    let s = seconds ?? skipBackwardInterval
    let newTime = max(currentTime - s, 0)
    seek(to: newTime)
  }

  func setPlaybackRate(_ rate: Float) {
    playbackRate = rate
    player?.rate = isPlaying ? rate : 0
    UserDefaults.standard.set(rate, forKey: Keys.playbackRate)
    updateNowPlayingPlaybackRate()
    logger.info("Playback rate set to \(rate)x")
  }

  func setVolume(_ vol: Float) {
    volume = max(0, min(1, vol))
    player?.volume = volume
  }

  // MARK: - Queue Management

  /// Add an episode to the end of the queue
  private func onQueueChanged() {
    PlaybackStateCoordinator.shared?.saveQueue(queue)
  }

  func addToQueue(_ episode: PlaybackEpisode) {
    // Don't add if already in queue or is current episode
    guard !queue.contains(where: { $0.id == episode.id }),
      currentEpisode?.id != episode.id
    else {
      logger.info("Episode already in queue or currently playing")
      return
    }
    // Enforce queue size limit
    guard queue.count < maxQueueSize else {
      logger.info("Queue is full (max \(self.maxQueueSize) episodes)")
      return
    }
    queue.append(episode)
    onQueueChanged()
    logger.info("Added to queue: \(episode.title) (\(self.queue.count)/\(self.maxQueueSize))")
  }

  /// Add an episode to play next (first position in queue)
  func playNext(_ episode: PlaybackEpisode) {
    // Check if already in queue (will be moved, not added)
    let wasInQueue = queue.contains(where: { $0.id == episode.id })
    // Remove if already in queue
    queue.removeAll { $0.id == episode.id }
    // Don't add if currently playing
    guard currentEpisode?.id != episode.id else {
      logger.info("Episode is currently playing")
      return
    }
    // Enforce queue size limit (only if adding new, not moving existing)
    if !wasInQueue && queue.count >= maxQueueSize {
      logger.info("Queue is full (max \(self.maxQueueSize) episodes)")
      return
    }
    queue.insert(episode, at: 0)
    onQueueChanged()
    logger.info("Play next: \(episode.title) (\(self.queue.count)/\(self.maxQueueSize))")
  }

  /// Remove an episode from the queue
  func removeFromQueue(_ episode: PlaybackEpisode) {
    queue.removeAll { $0.id == episode.id }
    onQueueChanged()
    logger.info("Removed from queue: \(episode.title)")
  }

  /// Remove episode at specific index
  func removeFromQueue(at index: Int) {
    guard index >= 0 && index < queue.count else { return }
    let episode = queue.remove(at: index)
    onQueueChanged()
    logger.info("Removed from queue at index \(index): \(episode.title)")
  }

  /// Move episode in queue
  func moveInQueue(from source: IndexSet, to destination: Int) {
    // Manual implementation of move since Array.move(fromOffsets:toOffset:) requires SwiftUI import
    var items = queue
    let sourceIndices = Array(source).sorted(by: >)

    // Remove items from source positions (in reverse to preserve indices)
    var movedItems: [PlaybackEpisode] = []
    for index in sourceIndices {
      movedItems.insert(items.remove(at: index), at: 0)
    }

    // Calculate adjusted destination
    let adjustedDestination = destination - source.filter { $0 < destination }.count

    // Insert at destination
    for (offset, item) in movedItems.enumerated() {
      items.insert(item, at: adjustedDestination + offset)
    }

    queue = items
    onQueueChanged()
  }

  /// Clear the entire queue
  func clearQueue() {
    queue.removeAll()
    onQueueChanged()
    logger.info("Queue cleared")
  }

  /// Update the list of auto-play candidates (unplayed episodes)
  func updateAutoPlayCandidates(_ episodes: [PlaybackEpisode]) {
    autoPlayCandidates = episodes
    logger.info("Updated auto-play candidates: \(episodes.count) episodes")
  }

  /// Add episodes to auto-play candidates (avoids duplicates)
  /// Caps the list at maxQueueSize to prevent unbounded memory growth
  func addToAutoPlayCandidates(_ episodes: [PlaybackEpisode]) {
    let existingIds = Set(autoPlayCandidates.map { $0.id })
    let newEpisodes = episodes.filter { !existingIds.contains($0.id) }
    autoPlayCandidates.append(contentsOf: newEpisodes)
    // Trim to max size to prevent unbounded memory growth
    if autoPlayCandidates.count > maxQueueSize {
      autoPlayCandidates = Array(autoPlayCandidates.suffix(maxQueueSize))
    }
    logger.info("Added \(newEpisodes.count) to auto-play candidates (total: \(self.autoPlayCandidates.count))")
  }

  /// Remove an episode from auto-play candidates (e.g., after fully played)
  func removeFromAutoPlayCandidates(_ episodeId: String) {
    autoPlayCandidates.removeAll { $0.id == episodeId }
  }

  /// Play the next episode in queue
  func playNextInQueue() {
    guard !queue.isEmpty else {
      logger.info("Queue is empty")
      return
    }

    let nextEpisode = queue.removeFirst()
    onQueueChanged()
    let savedPosition = PlaybackStateCoordinator.savedPlaybackPosition(
      podcastTitle: nextEpisode.podcastTitle,
      episodeTitle: nextEpisode.title
    )
    play(
      episode: nextEpisode,
      audioURL: nextEpisode.audioURL,
      startTime: savedPosition,
      imageURL: nextEpisode.imageURL,
      useDefaultSpeed: savedPosition == 0
    )
    logger.info("Playing next in queue: \(nextEpisode.title) at \(Int(savedPosition))s")
  }

  /// Skip to a specific episode in the queue
  func skipToQueueItem(at index: Int) {
    guard index >= 0 && index < queue.count else { return }

    // Remove all items before the selected one
    let episodesToRemove = Array(queue.prefix(index))
    queue.removeFirst(index)
    onQueueChanged()

    // Play the selected episode
    playNextInQueue()

    logger.info("Skipped \(episodesToRemove.count) episodes in queue")
  }

  // MARK: - Sleep Timer

  /// Set the sleep timer option
  func setSleepTimer(_ option: SleepTimerOption) {
    // Cancel existing timer
    sleepTimerTask?.cancel()
    sleepTimerTask = nil
    sleepTimerOption = option

    switch option {
    case .off:
      sleepTimerRemaining = 0
      logger.info("Sleep timer disabled")

    case .endOfEpisode:
      sleepTimerRemaining = 0  // Will be calculated dynamically
      logger.info("Sleep timer set to end of episode")

    default:
      if let timerDuration = option.duration {
        sleepTimerRemaining = timerDuration
        startSleepTimerCountdown()
        logger.info("Sleep timer set for \(timerDuration / 60) minutes")
      }
    }
  }

  /// Start the countdown timer
  private func startSleepTimerCountdown() {
    sleepTimerTask?.cancel()
    sleepTimerTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self else { return }
        // Exit loop if timer was turned off (e.g. triggerSleepTimer sets .off)
        guard self.sleepTimerOption != .off else { break }
        self.updateSleepTimer()
      }
    }
  }

  /// Update sleep timer countdown
  private func updateSleepTimer() {
    guard sleepTimerOption != .off else { return }

    if sleepTimerOption == .endOfEpisode {
      // No countdown for end of episode - handled in handlePlaybackEnded
      return
    }

    if sleepTimerRemaining > 0 {
      sleepTimerRemaining -= 1
    }

    if sleepTimerRemaining <= 0 {
      triggerSleepTimer()
    }
  }

  /// Trigger the sleep timer (pause playback)
  private func triggerSleepTimer() {
    logger.info("Sleep timer triggered - pausing playback")
    pause()
    sleepTimerTask?.cancel()
    sleepTimerTask = nil
    sleepTimerOption = .off
    sleepTimerRemaining = 0
  }

  /// Format remaining time for display
  var sleepTimerRemainingFormatted: String {
    guard sleepTimerRemaining > 0 else { return "" }
    let minutes = Int(sleepTimerRemaining) / 60
    let seconds = Int(sleepTimerRemaining) % 60
    if minutes > 0 {
      return String(format: "%d:%02d", minutes, seconds)
    } else {
      return String(format: "0:%02d", seconds)
    }
  }

  /// Check if sleep timer is active
  var isSleepTimerActive: Bool {
    sleepTimerOption != .off
  }

  /// Restore the last played episode on app launch (without playing)
  /// Flag indicating queue still needs restoration (coordinator wasn't ready at restore time)
  private var needsQueueRestore = false

  func restoreLastEpisode() {
    guard !hasRestoredLastEpisode else { return }
    hasRestoredLastEpisode = true

    // Restore persisted queue
    if let coordinator = PlaybackStateCoordinator.shared {
      queue = coordinator.restoreQueue()
    } else {
      needsQueueRestore = true
    }

    guard let state = loadLastPlaybackState() else {
      logger.info("No previous playback state to restore")
      return
    }

    // Just set the current episode info without playing
    currentEpisode = state.episode
    currentTime = state.time
    duration = state.duration  // Restore saved duration for correct progress display

    // No player yet, so the periodic observer won't correct the duration until
    // the user presses play. Load the true asset length now so the scrubber and
    // the transcript length-mismatch banner are honest before playback starts.
    if let url = resolvePlayableURL(for: state.episode) {
      loadRealDuration(from: url)
    }

    logger.info("Restored last episode: \(state.episode.title) at \(state.time)s / \(state.duration)s")
  }

  /// The URL we'd actually play for an episode: the downloaded local file when
  /// present, otherwise the remote audio URL.
  private func resolvePlayableURL(for episode: PlaybackEpisode) -> URL? {
    if case .downloaded(let localPath) = DownloadManager.shared.getDownloadState(
      episodeTitle: episode.title, podcastTitle: episode.podcastTitle),
      FileManager.default.fileExists(atPath: localPath)
    {
      return URL(fileURLWithPath: localPath)
    }
    return URL(string: episode.audioURL)
  }

  /// Asynchronously loads the real asset duration and overwrites the
  /// metadata-seeded value. RSS `itunes:duration` is often rounded or wrong,
  /// and ad-stitched mp3s differ from the original, so the true file length
  /// keeps the scrubber and the transcript length-mismatch banner accurate.
  /// No-op when the asset can't report a finite duration (offline remote URL
  /// or an indefinite live stream).
  private func loadRealDuration(from url: URL) {
    durationLoadTask?.cancel()
    let asset = AVURLAsset(url: url)
    durationLoadTask = Task { [weak self] in
      guard let loaded = try? await asset.load(.duration) else { return }
      let seconds = loaded.seconds
      guard seconds.isFinite, seconds > 0, !Task.isCancelled else { return }
      await MainActor.run {
        guard let self else { return }
        // Only overwrite when meaningfully different, to avoid scrubber jitter.
        guard abs(self.duration - seconds) > 1 else { return }
        self.duration = seconds
        self.updateNowPlayingDuration()
        self.savePlaybackState()
        self.updateWidgetPlaybackData()
      }
    }
  }

  /// Called after PlaybackStateCoordinator is initialized to restore queue if it was deferred
  func restoreQueueIfNeeded() {
    guard needsQueueRestore, let coordinator = PlaybackStateCoordinator.shared else { return }
    needsQueueRestore = false
    queue = coordinator.restoreQueue()
  }

  // MARK: - Caption Management

  private func loadCaptions(episode: PlaybackEpisode) {
    captionLoadTask?.cancel()
    captionLoadTask = Task {
      let fileStorage = FileStorageManager.shared

      if await fileStorage.captionFileExists(for: episode.title, podcastTitle: episode.podcastTitle)
      {
        do {
          let srtContent = try await fileStorage.loadCaptionFile(
            for: episode.title,
            podcastTitle: episode.podcastTitle
          )
          let segments = parseSRT(srtContent)

          guard !Task.isCancelled else { return }
          self.captionSegments = segments
          logger.info("Loaded \(segments.count) caption segments")
        } catch {
          logger.error("Failed to load captions: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
  }

  private func parseSRT(_ srtContent: String) -> [CaptionSegment] {
    var segments: [CaptionSegment] = []

    // Normalize line endings
    let normalizedText = srtContent.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    // Use pre-compiled static regex for SRT parsing
    guard let regex = Self.srtRegex else {
      logger.error("SRT regex not available")
      return segments
    }

    let nsText = normalizedText as NSString
    let matches = regex.matches(
      in: normalizedText, options: [], range: NSRange(location: 0, length: nsText.length))

    for (index, match) in matches.enumerated() {
      guard match.numberOfRanges >= 4 else { continue }

      let startTimeRange = match.range(at: 2)
      let endTimeRange = match.range(at: 3)

      guard startTimeRange.location != NSNotFound,
        endTimeRange.location != NSNotFound
      else { continue }

      let startTimeStr = nsText.substring(with: startTimeRange)
      let endTimeStr = nsText.substring(with: endTimeRange)

      guard let startTime = parseTimeString(startTimeStr),
        let endTime = parseTimeString(endTimeStr)
      else { continue }

      // Find text: starts after this match, ends at next match or end of string
      let textStart = match.range.location + match.range.length
      let textEnd: Int
      if index + 1 < matches.count {
        textEnd = matches[index + 1].range.location
      } else {
        textEnd = nsText.length
      }

      guard textStart < textEnd else { continue }

      let textRange = NSRange(location: textStart, length: textEnd - textStart)
      let text = nsText.substring(with: textRange)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\n", with: " ")

      guard !text.isEmpty else { continue }

      segments.append(
        CaptionSegment(
          startTime: startTime,
          endTime: endTime,
          text: text
        ))
    }

    return segments
  }

  private func parseTimeString(_ timeString: String) -> TimeInterval? {
    // Format: 00:00:10,500
    let components = timeString.replacingOccurrences(of: ",", with: ".").components(
      separatedBy: ":")
    guard components.count == 3 else { return nil }

    guard let hours = Double(components[0]),
      let minutes = Double(components[1]),
      let seconds = Double(components[2])
    else {
      return nil
    }

    return hours * 3600 + minutes * 60 + seconds
  }

  private func updateCurrentCaption() {
    guard !captionSegments.isEmpty else {
      if !currentCaption.isEmpty { currentCaption = "" }
      return
    }

    // Binary search for the caption segment at currentTime
    // captionSegments are sorted by startTime
    let time = currentTime
    var low = 0
    var high = captionSegments.count - 1
    var foundText = ""

    while low <= high {
      let mid = (low + high) / 2
      let segment = captionSegments[mid]

      if time < segment.startTime {
        high = mid - 1
      } else if time > segment.endTime {
        low = mid + 1
      } else {
        // time is within [startTime, endTime]
        foundText = segment.text
        break
      }
    }

    // Only write when value actually changed
    if currentCaption != foundText {
      currentCaption = foundText
    }
  }

  // MARK: - Now Playing Info

  private func updateNowPlayingInfo(imageURL: String? = nil) {
    guard let episode = currentEpisode else { return }

    var nowPlayingInfo = [String: Any]()
    nowPlayingInfo[MPMediaItemPropertyTitle] = episode.title
    nowPlayingInfo[MPMediaItemPropertyArtist] = episode.podcastTitle
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
    // Tell the system this is a podcast — lock screen / Control Center will
    // prefer the skipForward/skipBackward 15/30s buttons over next/previous
    // arrows, even though we register all four for AirPods gesture routing.
    nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

    // Load artwork asynchronously using URLSession (not Data(contentsOf:))
    if let imageURLString = imageURL ?? episode.imageURL,
      let url = URL(string: imageURLString)
    {
      artworkFetchTask?.cancel()
      artworkFetchTask = Task.detached { [weak self] in
        do {
          let (data, _) = try await URLSession.shared.data(from: url)
          #if os(iOS)
          if let image = UIImage(data: data) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run {
              var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
              info[MPMediaItemPropertyArtwork] = artwork
              MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
          }
          #else
          if let image = NSImage(data: data) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { size in
              let newImage = NSImage(size: size)
              newImage.lockFocus()
              image.draw(in: NSRect(origin: .zero, size: size))
              newImage.unlockFocus()
              return newImage
            }
            await MainActor.run {
              var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
              info[MPMediaItemPropertyArtwork] = artwork
              MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
          }
          #endif
        } catch {
          self?.logger.error("Failed to load artwork: \(error.localizedDescription, privacy: .public)")
        }
      }
    }
  }

  private func updateNowPlayingCurrentTime() {
    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  private func updateNowPlayingDuration() {
    guard duration > 0 else { return }
    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    logger.info("Updated Now Playing duration: \(Int(self.duration))s")
  }

  private func updateNowPlayingPlaybackRate() {
    var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }

  // MARK: - Widget Data Updates

  /// Update widget with current playback state.
  /// Always writes fresh data to shared UserDefaults (for progress bar).
  /// Only reloads the WidgetKit timeline when episode or play/pause state changes
  /// to avoid exhausting WidgetKit's daily reload budget.
  private func updateWidgetPlaybackData() {
    guard let episode = currentEpisode else {
      logger.debug("Widget: no current episode — clearing widget data")
      WidgetDataManager.clearPlaybackData()
      if lastWidgetAudioURL != nil {
        WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
        lastWidgetAudioURL = nil
        lastWidgetIsPlaying = nil
      }
      return
    }

    let data = WidgetPlaybackData(
      episodeTitle: episode.title,
      podcastTitle: episode.podcastTitle,
      imageURL: episode.imageURL,
      audioURL: episode.audioURL,
      currentTime: currentTime,
      duration: duration,
      isPlaying: isPlaying,
      lastUpdated: Date()
    )

    // Always write data so progress bar stays current
    WidgetDataManager.writePlaybackData(data)
    logger.debug("Widget: wrote data — episode=\"\(episode.title)\" isPlaying=\(self.isPlaying) progress=\(String(format: "%.1f%%", data.progress * 100))")

    // Only trigger a timeline reload (expensive, budget-limited) when the
    // episode or play/pause state actually changed — not on every 5-second tick
    let episodeChanged = episode.audioURL != lastWidgetAudioURL
    let playStateChanged = isPlaying != lastWidgetIsPlaying
    if episodeChanged || playStateChanged {
      logger.info("Widget: reloading timeline — episodeChanged=\(episodeChanged) playStateChanged=\(playStateChanged) episode=\"\(episode.title)\"")
      WidgetDataManager.cacheArtworkIfNeeded(from: episode.imageURL)
      WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
      lastWidgetAudioURL = episode.audioURL
      lastWidgetIsPlaying = isPlaying
    }
  }

  /// Update widget to show paused state (preserves last episode info)
  private func clearWidgetData() {
    guard let episode = currentEpisode else {
      WidgetDataManager.clearPlaybackData()
      WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
      return
    }

    let data = WidgetPlaybackData(
      episodeTitle: episode.title,
      podcastTitle: episode.podcastTitle,
      imageURL: episode.imageURL,
      audioURL: episode.audioURL,
      currentTime: currentTime,
      duration: duration,
      isPlaying: false,
      lastUpdated: Date()
    )
    WidgetDataManager.writePlaybackData(data)
    WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
  }

  /// Check if the widget requested a playback toggle
  private func checkWidgetTogglePlayback() {
    guard let defaults = WidgetDataManager.sharedDefaults else { return }
    // Force refresh — the widget extension writes from a different process
    defaults.synchronize()
    guard defaults.bool(forKey: "widgetTogglePlayback") else { return }
    defaults.set(false, forKey: "widgetTogglePlayback")
    defaults.synchronize()
    logger.info("Widget: Darwin notification received — isPlaying=\(self.isPlaying), toggling")
    if isPlaying {
      pause()
    } else {
      resume()
    }
  }

  /// Called when the app becomes active — handles the TOGGLE (pause) flag
  /// from TogglePlaybackIntent (Darwin notification fallback for cold launch).
  func handleWidgetToggleOnActive() {
    guard let defaults = WidgetDataManager.sharedDefaults else { return }
    defaults.synchronize()
    guard defaults.bool(forKey: "widgetTogglePlayback") else { return }
    defaults.set(false, forKey: "widgetTogglePlayback")
    defaults.synchronize()

    logger.info("Widget: toggle on active — isPlaying=\(self.isPlaying)")
    if isPlaying {
      pause()
    } else {
      resume()
    }
  }

  // MARK: - State Persistence

  /// Posts a notification with current playback position for SwiftData persistence
  private func postPlaybackPositionUpdate() {
    guard let episode = currentEpisode, duration > 0 else { return }

    let update = PlaybackPositionUpdate(
      episodeTitle: episode.title,
      podcastTitle: episode.podcastTitle,
      position: currentTime,
      duration: duration,
      audioURL: episode.audioURL
    )

    NotificationCenter.default.post(
      name: .playbackPositionDidUpdate,
      object: nil,
      userInfo: ["update": update]
    )
  }

  private func savePlaybackState(imageURL: String? = nil) {
    guard let episode = currentEpisode else { return }

    UserDefaults.standard.set(episode.title, forKey: Keys.lastEpisodeTitle)
    UserDefaults.standard.set(episode.podcastTitle, forKey: Keys.lastPodcastTitle)
    UserDefaults.standard.set(currentTime, forKey: Keys.lastPlaybackTime)
    // Don't overwrite a valid saved duration with 0 (AVPlayer may not have loaded yet)
    if duration > 0 {
      UserDefaults.standard.set(duration, forKey: Keys.lastDuration)
    }
    UserDefaults.standard.set(episode.audioURL, forKey: Keys.lastAudioURL)
    if let imageURL = imageURL {
      UserDefaults.standard.set(imageURL, forKey: Keys.lastImageURL)
    }
    if let desc = episode.episodeDescription {
      UserDefaults.standard.set(desc, forKey: Keys.lastEpisodeDescription)
    }
    if let pubDate = episode.pubDate {
      UserDefaults.standard.set(pubDate, forKey: Keys.lastEpisodePubDate)
    }
    if let guid = episode.guid {
      UserDefaults.standard.set(guid, forKey: Keys.lastEpisodeGuid)
    }

    logger.debug("Saved playback state: \(episode.title) at \(self.currentTime)s / \(self.duration)s")
  }

  func loadLastPlaybackState() -> (episode: PlaybackEpisode, time: TimeInterval, duration: TimeInterval, imageURL: String?)?
  {
    guard let title = UserDefaults.standard.string(forKey: Keys.lastEpisodeTitle),
      let podcastTitle = UserDefaults.standard.string(forKey: Keys.lastPodcastTitle),
      let audioURL = UserDefaults.standard.string(forKey: Keys.lastAudioURL)
    else {
      return nil
    }

    let time = UserDefaults.standard.double(forKey: Keys.lastPlaybackTime)
    let savedDuration = UserDefaults.standard.double(forKey: Keys.lastDuration)
    let imageURL = UserDefaults.standard.string(forKey: Keys.lastImageURL)

    let episodeDescription = UserDefaults.standard.string(forKey: Keys.lastEpisodeDescription)
    let pubDate = UserDefaults.standard.object(forKey: Keys.lastEpisodePubDate) as? Date
    let guid = UserDefaults.standard.string(forKey: Keys.lastEpisodeGuid)

    let episode = PlaybackEpisode(
      id: "\(podcastTitle)\(Self.episodeKeyDelimiter)\(title)",
      title: title,
      podcastTitle: podcastTitle,
      audioURL: audioURL,
      imageURL: imageURL,
      episodeDescription: episodeDescription,
      pubDate: pubDate,
      duration: savedDuration > 0 ? Int(savedDuration) : nil,
      guid: guid
    )

    return (episode, time, savedDuration, imageURL)
  }

  private func loadPlaybackRate() {
    let savedRate = UserDefaults.standard.float(forKey: Keys.playbackRate)
    playbackRate = savedRate > 0 ? savedRate : 1.0
  }

  func clearPlaybackState() {
    UserDefaults.standard.removeObject(forKey: Keys.lastEpisodeTitle)
    UserDefaults.standard.removeObject(forKey: Keys.lastPodcastTitle)
    UserDefaults.standard.removeObject(forKey: Keys.lastPlaybackTime)
    UserDefaults.standard.removeObject(forKey: Keys.lastDuration)
    UserDefaults.standard.removeObject(forKey: Keys.lastAudioURL)
    UserDefaults.standard.removeObject(forKey: Keys.lastImageURL)
    UserDefaults.standard.removeObject(forKey: Keys.lastEpisodeDescription)
    UserDefaults.standard.removeObject(forKey: Keys.lastEpisodePubDate)
    UserDefaults.standard.removeObject(forKey: Keys.lastEpisodeGuid)
  }

  // MARK: - Time Observer

  private func setupTimeObserver() {
    let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
    timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      [weak self] time in
      Task { @MainActor in
        guard let self = self else { return }

        let newTime = time.seconds

        // Duration updates can happen regardless of play state.
        if let newDuration = self.player?.currentItem?.duration.seconds,
          newDuration.isFinite, newDuration > 0
        {
          if self.duration != newDuration {
            self.duration = newDuration

            // Update Now Playing info whenever duration changes — covers both the
            // initial load (0 → real) and the RSS-metadata-vs-actual-file mismatch
            // case (e.g. 28 min metadata → 34 min actual due to ads).
            self.updateNowPlayingDuration()

            // Persist the corrected duration immediately so the next session
            // restores the accurate value rather than the stale RSS metadata.
            self.savePlaybackState()
            self.updateWidgetPlaybackData()
          }
        }

        // Skip currentTime/caption writes while paused. After
        // handlePlaybackEnded resets to 0 the periodic observer can still fire
        // once with the player's pre-reset time and clobber the 0.
        guard self.isPlaying, !self.suppressTimeObserverUntilSeekLands else { return }

        // Throttle currentTime writes — only update when changed by >0.2s
        if abs(newTime - self.currentTime) > 0.2 {
          self.currentTime = newTime
        }

        // Update current caption
        self.updateCurrentCaption()

        // Update Now Playing time every second (at 0.25s interval, ~every 4th tick)
        if Int(newTime) != Int(newTime - 0.25) {
          self.updateNowPlayingCurrentTime()
        }

        // Auto-save every 5 seconds and post notification for SwiftData persistence
        let currentSecond = Int(newTime)
        let previousSecond = Int(newTime - 0.25)
        if currentSecond % 5 == 0 && currentSecond != previousSecond {
          self.savePlaybackState()
          self.postPlaybackPositionUpdate()
          self.updateWidgetPlaybackData()
        }

        // Check for widget toggle playback request
        self.checkWidgetTogglePlayback()
      }
    }
  }

  // MARK: - Player Observers

  private func setupPlayerObservers(playerItem: AVPlayerItem) {
    // Cancel any existing player observer tasks
    playerEndedTask?.cancel()
    playerStalledTask?.cancel()

    // Observe playback end using Task-based async sequence
    playerEndedTask = Task { @MainActor [weak self, weak playerItem] in
      guard let playerItem else { return }
      for await _ in NotificationCenter.default.notifications(named: .AVPlayerItemDidPlayToEndTime, object: playerItem) {
        self?.handlePlaybackEnded()
      }
    }

    // Observe playback stall using Task-based async sequence
    playerStalledTask = Task { [weak self, weak playerItem] in
      guard let playerItem else { return }
      for await _ in NotificationCenter.default.notifications(named: .AVPlayerItemPlaybackStalled, object: playerItem) {
        self?.logger.warning("Playback stalled")
      }
    }
  }

  private func handlePlaybackEnded() {
    logger.info("Playback ended")
    isPlaying = false

    // Persist a final position == duration so PlaybackStateCoordinator flips
    // model.isCompleted = true and downstream views (EpisodeListView,
    // Library lists) re-render to the replay state. The periodic 5s save
    // alone can miss the actual end since the last tick may land seconds
    // before AVPlayerItemDidPlayToEndTime fires.
    if duration > 0 {
      currentTime = duration
      postPlaybackPositionUpdate()
    }

    // Remove current episode from auto-play candidates (it's been fully played)
    if let currentId = currentEpisode?.id {
      removeFromAutoPlayCandidates(currentId)
    }

    // Check if sleep timer is set to "end of episode"
    if sleepTimerOption == .endOfEpisode {
      logger.info("Sleep timer: end of episode reached - stopping playback")
      sleepTimerOption = .off
      sleepTimerRemaining = 0
      currentTime = 0
      clearPlaybackState()
      return
    }

    // Check if there's a next episode in queue
    if !queue.isEmpty {
      logger.info("Playing next episode from queue")
      currentTime = 0
      playNextInQueue()
      return
    }

    // Check auto-play setting and try to play random unplayed episode
    let autoPlayEnabled = UserDefaults.standard.bool(forKey: Keys.autoPlayNextEpisode)
    if autoPlayEnabled, !autoPlayCandidates.isEmpty {
      // Pick the top-scored episode (candidates are kept in Up Next order)
      let nextEpisode = autoPlayCandidates[0]
      let savedPosition = PlaybackStateCoordinator.savedPlaybackPosition(
        podcastTitle: nextEpisode.podcastTitle,
        episodeTitle: nextEpisode.title
      )
      logger.info("Auto-playing next episode: \(nextEpisode.title) at \(Int(savedPosition))s")
      currentTime = 0
      play(
        episode: nextEpisode,
        audioURL: nextEpisode.audioURL,
        startTime: savedPosition,
        imageURL: nextEpisode.imageURL,
        useDefaultSpeed: savedPosition == 0
      )
      return
    }

    // No follow-up — leave the episode loaded but rewind the player to zero so
    // tapping Play actually replays from the start instead of sitting at the
    // end of the item (where AVPlayer.play() is a no-op). The suppress flag
    // keeps the periodic time observer from clobbering currentTime with the
    // pre-seek position before the seek completes.
    suppressTimeObserverUntilSeekLands = true
    currentTime = 0
    updateNowPlayingCurrentTime()
    updateNowPlayingPlaybackRate()
    player?.pause()
    player?.seek(
      to: .zero,
      toleranceBefore: .zero,
      toleranceAfter: .zero
    ) { [weak self] _ in
      Task { @MainActor in
        self?.suppressTimeObserverUntilSeekLands = false
      }
    }
    clearPlaybackState()
  }

  // MARK: - Cleanup

  private func cleanup() {
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
      timeObserver = nil
    }

    // Cancel Task-based observers
    interruptionResumeTask?.cancel()
    interruptionResumeTask = nil
    playerEndedTask?.cancel()
    playerEndedTask = nil
    playerStalledTask?.cancel()
    playerStalledTask = nil
    artworkFetchTask?.cancel()
    artworkFetchTask = nil
    captionLoadTask?.cancel()
    captionLoadTask = nil
    durationLoadTask?.cancel()
    durationLoadTask = nil

    player?.pause()
    player = nil
  }

  // Note: This is a singleton designed to live for the app's lifetime.
  // No deinit needed - the singleton is never deallocated.
}

// MARK: - Supporting Models

struct PlaybackEpisode: Identifiable, Codable, Sendable, Equatable {
  let id: String
  let title: String
  let podcastTitle: String
  let audioURL: String
  var imageURL: String?
  var episodeDescription: String?
  var pubDate: Date?
  var duration: Int?
  var guid: String?
}

struct CaptionSegment: Identifiable, Sendable {
  let id = UUID()
  let startTime: TimeInterval
  let endTime: TimeInterval
  let text: String
}
