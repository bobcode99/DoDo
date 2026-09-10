//
//  AISettingsTab.swift
//  PodcastAnalyzer
//
//  AI pane of the macOS Preferences window.
//

#if os(macOS)
import SwiftData
import SwiftUI

/// Renders the AI provider configuration UI inline in the Settings tab
/// instead of pushing a sheet — keeps every Settings pane on one page.
struct AISettingsTab: View {
  var body: some View {
    AISettingsView()
  }
}


#endif
