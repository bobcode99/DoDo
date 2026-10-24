//
//  SettingsRoute.swift
//  PodcastAnalyzer
//
//  Destinations pushed on the Settings tab's NavigationStack. Value-based so the
//  tab's path binding sees every push, and so a screen is built when it is shown
//  rather than when its row is.
//

enum SettingsRoute: Hashable {
  case syncNotifications
  case downloads
  case playback
  case transcripts
  case aiAnalysis
  case translation
  case subscriptions
  case listeningStats
  case storage
  case appearance
  case general

  case autoDownloadShows
  case autoTranscription
  case transcriptContext
  #if DEBUG
  case shortcutsDebug
  #endif
}
