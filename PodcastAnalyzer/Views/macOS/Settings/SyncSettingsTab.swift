//
//  SyncSettingsTab.swift
//  PodcastAnalyzer
//
//  Sync pane of the macOS Preferences window.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct SyncSettingsTab: View {
  let viewModel: SettingsViewModel
  @AppStorage("allowAutoDownloadOnBattery") private var allowAutoDownloadOnBattery = false
  @AppStorage("episodeCacheLimit") private var episodeCacheLimit = 0

  private let cacheLimitOptions: [(label: String, value: Int)] = [
    ("Unlimited", 0),
    ("5 episodes", 5),
    ("10 episodes", 10),
    ("25 episodes", 25),
    ("50 episodes", 50)
  ]

  var body: some View {
    @Bindable var syncManager = BackgroundSyncManager.shared
    @Bindable var viewModel = viewModel

    Form {
      Section {
        Toggle("Enable Background Sync", isOn: $syncManager.isBackgroundSyncEnabled)

        if syncManager.isBackgroundSyncEnabled {
          Toggle("New Episode Notifications", isOn: $syncManager.isNotificationsEnabled)

          Toggle("Auto-Download New Episodes", isOn: $viewModel.autoDownloadNewEpisodes)
            .onChange(of: viewModel.autoDownloadNewEpisodes) { _, newValue in
              viewModel.setAutoDownloadNewEpisodes(newValue)
            }

          if let lastSync = syncManager.lastSyncDate {
            LabeledContent("Last Sync") {
              Text(Formatters.formatDate(lastSync, time: .shortened))
                .foregroundStyle(.secondary)
            }
          }

          Button("Sync Now") {
            Task {
              await syncManager.syncNow()
            }
          }
          .disabled(syncManager.isSyncing)
        }
      } header: {
        Text("Sync Settings")
      } footer: {
        Text("Automatically check for new episodes periodically while the app is running.")
      }

      Section {
        Toggle(isOn: $allowAutoDownloadOnBattery) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Download on Battery")
            Text("Allow auto-downloads when the Mac isn't plugged in")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Picker("Episode Cache Limit", selection: $episodeCacheLimit) {
          ForEach(cacheLimitOptions, id: \.value) { option in
            Text(option.label).tag(option.value)
          }
        }
      } header: {
        Text("Auto-Download")
      } footer: {
        Text("Per-podcast settings (Always / Never / Use Global) are in each podcast's context menu. Cache limit caps total auto-downloaded episodes; 0 = unlimited.")
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}


#endif
