//
//  PlaybackSettingsTab.swift
//  PodcastAnalyzer
//
//  Playback pane of the macOS Preferences window.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct PlaybackSettingsTab: View {
  let viewModel: SettingsViewModel
  private let playbackSpeeds: [Float] = Formatters.playbackSpeeds
  private let skipIntervalOptions: [Int] = [5, 10, 15, 20, 30, 45, 60]

  var body: some View {
    @Bindable var viewModel = viewModel

    Form {
      Section {
        Picker("Default Playback Speed", selection: $viewModel.defaultPlaybackSpeed) {
          ForEach(playbackSpeeds, id: \.self) { speed in
            Text(Formatters.formatSpeed(speed)).tag(speed)
          }
        }
        .onChange(of: viewModel.defaultPlaybackSpeed) { _, newValue in
          viewModel.setDefaultPlaybackSpeed(newValue)
        }

        Picker("Skip Back", selection: Binding(
          get: { viewModel.skipBackwardInterval },
          set: { viewModel.setSkipBackwardInterval($0) }
        )) {
          ForEach(skipIntervalOptions, id: \.self) { seconds in
            Text("\(seconds)s").tag(seconds)
          }
        }

        Picker("Skip Forward", selection: Binding(
          get: { viewModel.skipForwardInterval },
          set: { viewModel.setSkipForwardInterval($0) }
        )) {
          ForEach(skipIntervalOptions, id: \.self) { seconds in
            Text("\(seconds)s").tag(seconds)
          }
        }

        Toggle("Auto-Play Next Episode", isOn: $viewModel.autoPlayNextEpisode)
          .onChange(of: viewModel.autoPlayNextEpisode) { _, newValue in
            viewModel.setAutoPlayNextEpisode(newValue)
          }
      } header: {
        Text("Playback")
      } footer: {
        Text("Skip intervals apply to in-app controls and lock screen/headphone buttons.")
      }
    }
    .formStyle(.grouped)
    .padding()
  }

}


#endif
