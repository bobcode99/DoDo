//
//  SettingsView.swift
//  PodcastAnalyzer
//
//  Category list. Every setting used to live on this one screen — 13 sections
//  and ~35 controls deep — which meant finding anything required reading all of
//  it. Now the top level is a short list of destinations grouped by what the
//  user is trying to do, with current state shown on the right so the common
//  question ("which engine am I on?") is answered without opening anything.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
  @State private var viewModel = SettingsViewModel()
  @Environment(\.modelContext) private var modelContext

  private var syncManager: BackgroundSyncManager { .shared }

  var body: some View {
    List {
      // Automation: the things the app does on its own.
      Section {
        NavigationLink(value: SettingsRoute.syncNotifications) {
          SettingsRowLabel(
            title: "Sync & Notifications",
            systemImage: "arrow.triangle.2.circlepath",
            tint: .blue,
            value: syncManager.isBackgroundSyncEnabled ? Text("On") : Text("Off")
          )
        }

        NavigationLink(value: SettingsRoute.downloads) {
          SettingsRowLabel(
            title: "Downloads",
            systemImage: "arrow.down.circle.fill",
            tint: .indigo,
            value: viewModel.autoDownloadNewEpisodes ? Text("Automatic") : Text("Manual")
          )
        }

        NavigationLink(value: SettingsRoute.playback) {
          SettingsRowLabel(
            title: "Playback",
            systemImage: "play.fill",
            tint: .orange,
            value: Text(verbatim: Formatters.formatSpeed(viewModel.defaultPlaybackSpeed))
          )
        }
      }

      // Understanding an episode: transcript in, analysis out.
      Section {
        NavigationLink(value: SettingsRoute.transcripts) {
          SettingsRowLabel(
            title: "Transcripts",
            systemImage: "text.quote",
            tint: .teal,
            value: Text(verbatim: viewModel.selectedTranscriptEngine.displayName)
          )
        }

        NavigationLink(value: SettingsRoute.aiAnalysis) {
          SettingsRowLabel(
            title: "AI Analysis",
            systemImage: "sparkles",
            tint: .purple,
            value: AISettingsManager.shared.hasConfiguredProvider
              ? Text(verbatim: AISettingsManager.shared.selectedProvider.displayName)
              : Text("Not set up"),
            valueTint: AISettingsManager.shared.hasConfiguredProvider ? .secondary : .orange
          )
        }

        NavigationLink(value: SettingsRoute.translation) {
          SettingsRowLabel(
            title: "Translation",
            systemImage: "translate",
            tint: .cyan,
            value: Text(verbatim: SubtitleSettingsManager.shared.targetLanguage.displayName)
          )
        }
      }

      // The library itself.
      Section {
        NavigationLink(value: SettingsRoute.subscriptions) {
          SettingsRowLabel(title: "Subscriptions", systemImage: "square.stack.3d.up.fill", tint: .green)
        }

        NavigationLink(value: SettingsRoute.listeningStats) {
          SettingsRowLabel(title: "Listening Stats", systemImage: "chart.bar.fill", tint: .pink)
        }

        NavigationLink(value: SettingsRoute.storage) {
          SettingsRowLabel(title: "Storage", systemImage: "externaldrive.fill", tint: .gray)
        }
      }

      Section {
        NavigationLink(value: SettingsRoute.appearance) {
          SettingsRowLabel(title: "Appearance", systemImage: "paintbrush.fill", tint: .brown)
        }

        NavigationLink(value: SettingsRoute.general) {
          SettingsRowLabel(title: "General", systemImage: "gear", tint: .secondary)
        }
      }
    }
    #if os(iOS)
    .listStyle(.insetGrouped)
    #else
    .listStyle(.sidebar)
    #endif
    .navigationTitle("Settings")
    .platformToolbarTitleDisplayMode()
    .navigationDestination(for: SettingsRoute.self) { route in
      destination(for: route)
    }
    .onAppear {
      viewModel.loadFeeds(modelContext: modelContext)
      viewModel.checkTranscriptModelStatus()
      WhisperModelManager.shared.checkAllModelStatuses()
    }
  }
}

extension SettingsView {
  @ViewBuilder
  fileprivate func destination(for route: SettingsRoute) -> some View {
    switch route {
    case .syncNotifications: SyncSettingsScreen()
    case .downloads: DownloadSettingsScreen(viewModel: viewModel)
    case .playback: PlaybackSettingsScreen(viewModel: viewModel)
    case .transcripts: TranscriptSettingsScreen(viewModel: viewModel)
    case .aiAnalysis: AISettingsView()
    case .translation: TranslationSettingsScreen()
    case .subscriptions: SubscriptionsSettingsScreen(viewModel: viewModel)
    case .listeningStats: ListeningStatsView()
    case .storage: DataManagementView()
    case .appearance: AppearanceSettingsScreen(viewModel: viewModel)
    case .general: GeneralSettingsScreen(viewModel: viewModel)
    case .autoDownloadShows: AutoDownloadShowsView()
    case .autoTranscription: AutoTranscribeManagementView()
    case .transcriptContext: TranscriptContextManagementView()
    #if DEBUG
    case .shortcutsDebug: ShortcutsDebugView()
    #endif
    }
  }
}

#Preview {
  NavigationStack {
    SettingsView()
  }
}
