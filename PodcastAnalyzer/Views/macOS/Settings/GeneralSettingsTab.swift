//
//  GeneralSettingsTab.swift
//  PodcastAnalyzer
//
//  General pane of the macOS Preferences window.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct GeneralSettingsTab: View {
  let viewModel: SettingsViewModel
  @State private var showAddFeedSheet = false
  @State private var showListeningStats = false
  @State private var showImportInstructions = false
  @State private var showingRegions = false
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    @Bindable var viewModel = viewModel

    Form {
      Section {
        Button("Add RSS Feed") {
          showAddFeedSheet = true
        }
        Button("Import Podcasts…") {
          showImportInstructions = true
        }
      } header: {
        Text("Subscriptions")
      } footer: {
        Text("Add by RSS URL or import an OPML file exported from Apple Podcasts.")
      }

      Section {
        Button {
          showingRegions = true
        } label: {
          HStack {
            Text("Discovery Regions")
            Spacer()
            Text(DiscoveryRegions.shared.enabledStorefronts.map(\.flag).joined())
              .foregroundStyle(.secondary)
          }
        }
      } header: {
        Text("Discovery")
      } footer: {
        Text("Countries whose top podcasts Home offers.")
      }

      Section {
        Button("Listening Stats") {
          showListeningStats = true
        }
      } header: {
        Text("Insights")
      } footer: {
        Text("View your listening history, top shows, and trends.")
      }

      Section {
        Picker("App Language", selection: Binding(
          get: { LanguageManager.shared.appLanguage },
          set: { LanguageManager.shared.appLanguage = $0 }
        )) {
          ForEach(LanguageManager.availableLanguages) { language in
            Text(language.displayName).tag(language.id)
          }
        }
      } header: {
        Text("Language")
      } footer: {
        Text("Choose the language for the app interface. 'System Default' follows your device language.")
      }

      Section {
        LabeledContent("Version") {
          Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("About")
      }
    }
    .formStyle(.grouped)
    .padding()
    .sheet(isPresented: $showingRegions) {
      DiscoveryRegionsView()
    }
    .sheet(isPresented: $showAddFeedSheet) {
      AddFeedView(viewModel: viewModel, modelContext: modelContext) {
        showAddFeedSheet = false
      }
    }
    .sheet(isPresented: $showListeningStats) {
      NavigationStack {
        ListeningStatsView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { showListeningStats = false }
            }
          }
      }
      .frame(minWidth: 500, minHeight: 400)
    }
    .sheet(isPresented: $showImportInstructions) {
      NavigationStack {
        ScrollView {
          ImportShortcutInstructionsView()
            .padding()
        }
        .navigationTitle("Import from Apple Podcasts")
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { showImportInstructions = false }
          }
        }
      }
      .frame(minWidth: 440, minHeight: 480)
    }
    .onAppear {
      viewModel.loadFeeds(modelContext: modelContext)
    }
  }
}


#endif
