//
//  OpenPlayerControl.swift
//  PodcastAnalyzerWidget
//
//  Control Center button that opens the DoDo player. The system's own Now
//  Playing module can't do this — tapping it gives the app no signal (no
//  public API tells a third-party app it was opened from Now Playing).
//

#if os(iOS)
import AppIntents
import SwiftUI
import WidgetKit

/// Matches the app target's OpenNowPlayingIntent, which is the copy that runs
/// (`.foreground` opens the app first). This one only falls back to the URL.
struct OpenNowPlayingIntent: AppIntent {
  static let title: LocalizedStringResource = "Open Now Playing"
  static let description = IntentDescription("Opens the DoDo player.")

  static var supportedModes: IntentModes { .foreground }

  func perform() async throws -> some IntentResult & OpensIntent {
    .result(opensIntent: OpenURLIntent(URL(string: "podcastanalyzer://expandplayer")!))
  }
}

struct OpenPlayerControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: "com.jn.PodcastAnalyzer.OpenPlayerControl") {
      ControlWidgetButton(action: OpenNowPlayingIntent()) {
        Label("DoDo Player", systemImage: "waveform")
      }
    }
    .displayName("DoDo Player")
    .description("Open the DoDo player.")
  }
}
#endif
