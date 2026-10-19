//
//  PodcastAnalyzerWidgetBundle.swift
//  PodcastAnalyzerWidget
//

import SwiftUI
import WidgetKit

@main
struct PodcastAnalyzerWidgetBundle: WidgetBundle {
  var body: some Widget {
    NowPlayingWidget()
    #if os(iOS)
    OpenPlayerControl()
    #endif
  }
}
