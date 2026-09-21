//
//  TogglePlaybackIntent.swift
//  PodcastAnalyzerWidget
//
//  AppIntent for toggling playback from widget button.
//  Conforms to AudioPlaybackIntent so iOS can run it without bringing the app
//  to the foreground. Posts a Darwin notification so the main app process can
//  react immediately when it is alive in the background (audio playing).
//

import AppIntents
import CoreFoundation
import Foundation
import WidgetKit

// MARK: - Resume Playback Intent (background — used for play button)

/// Resumes playback without opening the app (AudioPlaybackIntent).
/// The main app target has a matching ResumePlaybackIntent where perform()
/// directly calls EnhancedAudioManager. This widget-side version is a
/// fallback that uses cross-process signaling.
struct ResumePlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Resume Playback"
  static let description: IntentDescription = "Resumes podcast playback in the background"

  func perform() async throws -> some IntentResult {
    // Post Darwin notification so the main app can resume immediately
    let name = "com.jn.PodcastAnalyzer.resumePlayback" as CFString
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(rawValue: name),
      nil, nil, true
    )

    // Optimistically set isPlaying to true so the widget re-renders with pause icon
    if let current = WidgetDataManager.readPlaybackData() {
      let optimistic = WidgetPlaybackData(
        episodeTitle: current.episodeTitle,
        podcastTitle: current.podcastTitle,
        imageURL: current.imageURL,
        audioURL: current.audioURL,
        currentTime: current.currentTime,
        duration: current.duration,
        isPlaying: true,
        lastUpdated: current.lastUpdated
      )
      WidgetDataManager.writePlaybackData(optimistic)
    }

    WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
    return .result()
  }
}

// MARK: - Toggle Playback Intent (background only — used for pause button when app is alive)

struct TogglePlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Toggle Playback"
  static let description: IntentDescription = "Play or pause the current episode"

  func perform() async throws -> some IntentResult {
    guard let defaults = WidgetDataManager.sharedDefaults else {
      return .result()
    }
    // Set a flag the main app reads when it becomes active (covers cold-launch case)
    defaults.set(true, forKey: "widgetTogglePlayback")
    defaults.synchronize()
    // Post a Darwin notification so the main app can toggle immediately
    // if it is alive in the background playing audio.
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName("com.jn.PodcastAnalyzer.togglePlayback" as CFString),
      nil, nil, true
    )

    // Optimistically flip isPlaying in shared UserDefaults so the widget
    // re-renders immediately with the correct icon — before the main app
    // has had a chance to write the authoritative state back.
    if let current = WidgetDataManager.readPlaybackData() {
      let optimistic = WidgetPlaybackData(
        episodeTitle: current.episodeTitle,
        podcastTitle: current.podcastTitle,
        imageURL: current.imageURL,
        audioURL: current.audioURL,
        currentTime: current.currentTime,
        duration: current.duration,
        isPlaying: !current.isPlaying,
        lastUpdated: current.lastUpdated
      )
      WidgetDataManager.writePlaybackData(optimistic)
    }

    // Force an immediate re-render with the optimistic state.
    WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
    return .result()
  }
}
