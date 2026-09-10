//
//  MacSettingsView.swift
//  PodcastAnalyzer
//
//  macOS-specific settings view for Preferences window (Cmd+,)
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacSettingsView: View {
  private enum SettingsTab: Hashable, CaseIterable {
    case general, appearance, sync, playback, transcript, ai, mcp, storage

    var title: LocalizedStringKey {
      switch self {
      case .general: "General"
      case .appearance: "Appearance"
      case .sync: "Sync"
      case .playback: "Playback"
      case .transcript: "Transcript"
      case .ai: "AI"
      case .mcp: "MCP"
      case .storage: "Storage"
      }
    }

    var systemImage: String {
      switch self {
      case .general: "gearshape"
      case .appearance: "paintbrush"
      case .sync: "arrow.triangle.2.circlepath"
      case .playback: "play.circle"
      case .transcript: "text.bubble"
      case .ai: "sparkles"
      case .mcp: "network"
      case .storage: "internaldrive"
      }
    }
  }

  @State private var selection: SettingsTab = .general
  @State private var viewModel = SettingsViewModel()

  var body: some View {
    TabView(selection: $selection) {
      ForEach(SettingsTab.allCases, id: \.self) { tab in
        Tab(tab.title, systemImage: tab.systemImage, value: tab) {
          tabContent(for: tab)
        }
      }
    }
    .frame(maxWidth: 560, minHeight: 300)
    .scenePadding()
  }

  @ViewBuilder
  private func tabContent(for tab: SettingsTab) -> some View {
    switch tab {
    case .general: GeneralSettingsTab(viewModel: viewModel)
    case .appearance: AppearanceSettingsTab(viewModel: viewModel)
    case .sync: SyncSettingsTab(viewModel: viewModel)
    case .playback: PlaybackSettingsTab(viewModel: viewModel)
    case .transcript: TranscriptSettingsTab(viewModel: viewModel)
    case .ai: AISettingsTab()
    case .mcp: MacMCPSettingsView()
    case .storage: StorageSettingsTab()
    }
  }
}


#Preview {
  MacSettingsView()
}

#endif
