//
//  OpenNowPlayingIntent.swift
//  PodcastAnalyzer
//
//  Action of the "DoDo Player" Control Center control. The widget extension
//  has a matching type (PodcastAnalyzerWidget/OpenPlayerControl.swift); being
//  `.foreground`, the system opens the app and runs this copy.
//

#if os(iOS)
import AppIntents

struct OpenNowPlayingIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Now Playing"
  static let description = IntentDescription("Opens the DoDo player.")

  static var supportedModes: IntentModes { .foreground }

  @MainActor
  func perform() async throws -> some IntentResult {
    NotificationNavigationManager.shared.requestExpandPlayer()
    return .result()
  }
}
#endif
