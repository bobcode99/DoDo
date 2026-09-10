//
//  AppearanceSettingsTab.swift
//  PodcastAnalyzer
//
//  Appearance pane of the macOS Preferences window.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct AppearanceSettingsTab: View {
  let viewModel: SettingsViewModel

  @AppStorage(AppThemeDefaults.key) private var themeRaw = AppTheme.system.rawValue
  @AppStorage(AppAccentColorDefaults.key) private var accentRaw = ""

  private var accentColor: Color {
    AppAccentColorDefaults.decode(accentRaw) ?? .accentColor
  }

  var body: some View {
    @Bindable var viewModel = viewModel

    Form {
      Section {
        Picker("Appearance", selection: $themeRaw) {
          ForEach(AppTheme.allCases) { theme in
            Label(theme.titleKey, systemImage: theme.systemImage).tag(theme.rawValue)
          }
        }

        ColorPicker("Accent Colour", selection: Binding(
          get: { accentColor },
          set: { accentRaw = AppAccentColorDefaults.encode($0) }
        ), supportsOpacity: false)

        if !accentRaw.isEmpty {
          Button("Use System Default") { accentRaw = "" }
        }
      } header: {
        Text("Theme")
      } footer: {
        Text("System follows your Mac's Light/Dark setting.")
      }

      Section {
        Toggle("Show Episode Artwork", isOn: $viewModel.showEpisodeArtwork)
          .onChange(of: viewModel.showEpisodeArtwork) { _, newValue in
            viewModel.setShowEpisodeArtwork(newValue)
          }

        Toggle("Trending Episodes", isOn: $viewModel.showTrendingEpisodes)
          .onChange(of: viewModel.showTrendingEpisodes) { _, newValue in
            viewModel.setShowTrendingEpisodes(newValue)
          }
      } header: {
        Text("Episode Lists")
      } footer: {
        Text("Show AI-powered episode suggestions and trending episodes on Home. Hide artwork to reduce memory usage.")
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}


#endif
