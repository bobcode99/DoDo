//
//  PlaybackIntents.swift
//  PodcastAnalyzerWidget
//
//  Play/pause buttons for the Now Playing widget. The app target defines the
//  same two AudioPlaybackIntents (WidgetResumePlaybackIntent.swift) and iOS runs
//  those, in the app process, against the real player. These copies only exist
//  so the widget can build Button(intent:).
//
//  They deliberately don't write an optimistic isPlaying: the app's pause()/
//  resume() write the real state and reload the timeline, and a guessed state
//  the app never confirms is how the button ended up showing the wrong icon.
//

import AppIntents

struct ResumePlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Resume Playback"
  static let description: IntentDescription = "Resumes podcast playback in the background"

  func perform() async throws -> some IntentResult { .result() }
}

struct PausePlaybackIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Pause Playback"
  static let description: IntentDescription = "Pauses podcast playback in the background"

  func perform() async throws -> some IntentResult { .result() }
}
