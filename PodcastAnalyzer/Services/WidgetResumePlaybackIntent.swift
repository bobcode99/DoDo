//
//  WidgetResumePlaybackIntent.swift
//  PodcastAnalyzer
//
//  App-side handler for the widget play button.
//  Conforms to AudioPlaybackIntent so iOS runs it in the background
//  without bringing the app to the foreground — same as the pause button.
//  The widget extension defines a matching ResumePlaybackIntent;
//  iOS routes perform() here (matched by type name).
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
