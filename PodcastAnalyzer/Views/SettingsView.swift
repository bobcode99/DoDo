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
        NavigationLink {
          SyncSettingsScreen()
        } label: {
          SettingsRowLabel(
            title: "Sync & Notifications",
            systemImage: "arrow.triangle.2.circlepath",
            tint: .blue,
            value: syncManager.isBackgroundSyncEnabled ? Text("On") : Text("Off")
          )
        }

        NavigationLink {
          DownloadSettingsScreen(viewModel: viewModel)
        } label: {
          SettingsRowLabel(
            title: "Downloads",
            systemImage: "arrow.down.circle.fill",
            tint: .indigo,
            value: viewModel.autoDownloadNewEpisodes ? Text("Automatic") : Text("Manual")
          )
        }

        NavigationLink {
          PlaybackSettingsScreen(viewModel: viewModel)
        } label: {
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
        NavigationLink {
          TranscriptSettingsScreen(viewModel: viewModel)
        } label: {
          SettingsRowLabel(
            title: "Transcripts",
            systemImage: "text.quote",
            tint: .teal,
            value: Text(verbatim: viewModel.selectedTranscriptEngine.displayName)
          )
        }

        NavigationLink {
          AISettingsView()
        } label: {
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

        NavigationLink {
          TranslationSettingsScreen()
        } label: {
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
        NavigationLink {
          SubscriptionsSettingsScreen(viewModel: viewModel)
        } label: {
          SettingsRowLabel(title: "Subscriptions", systemImage: "square.stack.3d.up.fill", tint: .green)
        }

        NavigationLink {
          ListeningStatsView()
        } label: {
          SettingsRowLabel(title: "Listening Stats", systemImage: "chart.bar.fill", tint: .pink)
        }

        NavigationLink {
          DataManagementView()
        } label: {
          SettingsRowLabel(title: "Storage", systemImage: "externaldrive.fill", tint: .gray)
        }
      }

      Section {
        NavigationLink {
          AppearanceSettingsScreen(viewModel: viewModel)
        } label: {
          SettingsRowLabel(title: "Appearance", systemImage: "paintbrush.fill", tint: .brown)
        }

        NavigationLink {
          GeneralSettingsScreen(viewModel: viewModel)
        } label: {
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
    .onAppear {
      viewModel.loadFeeds(modelContext: modelContext)
      viewModel.checkTranscriptModelStatus()
      WhisperModelManager.shared.checkAllModelStatuses()
    }
  }
}

#Preview {
  NavigationStack {
    SettingsView()
  }
}
