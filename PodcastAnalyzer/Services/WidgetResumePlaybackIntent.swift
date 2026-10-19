//
//  WidgetResumePlaybackIntent.swift
//  PodcastAnalyzer
//
//  App-side handlers for the widget play and pause buttons.
//  Conform to AudioPlaybackIntent so iOS runs them in the background
//  without bringing the app to the foreground.
//  The widget extension defines matching ResumePlaybackIntent and
//  PausePlaybackIntent; iOS routes perform() here (matched by type name).
//

import AppIntents
import OSLog

struct ResumePlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Resume Playback"
  static let description: IntentDescription = "Resumes podcast playback in the background"

  private static let logger = Logger(subsystem: "com.podcast.analyzer", category: "WidgetResume")

  func perform() async throws -> some IntentResult {
    Self.logger.info("ResumePlaybackIntent.perform() called in app process")

    await MainActor.run {
      let audioManager = EnhancedAudioManager.shared

      guard !audioManager.isPlaying else {
        Self.logger.info("Already playing — nothing to do")
        return
      }

      // Ensure the last episode is loaded (may not be if app was suspended)
      if audioManager.currentEpisode == nil {
        audioManager.restoreLastEpisode()
      }

      // resume() handles all cases:
      // - player exists → play()
      // - player nil + currentEpisode set → creates player and plays
      audioManager.resume()
      Self.logger.info("Playback resumed from widget intent")
    }

    return .result()
  }
}

/// Explicit pause, not a toggle: the button is only shown while the widget says
/// "playing", and a toggle fired from a stale widget would start audio instead.
struct PausePlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Pause Playback"
  static let description: IntentDescription = "Pauses podcast playback in the background"

  @MainActor
  func perform() async throws -> some IntentResult {
    // On a cold launch, creating `shared` also corrects a widget left on "playing".
    let audioManager = EnhancedAudioManager.shared
    if audioManager.isPlaying {
      audioManager.pause()
    }
    return .result()
  }
}
