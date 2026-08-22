//
//  PodcastPlaybackSettingsView.swift
//  PodcastAnalyzer
//
//  Per-show playback settings: speed, intro/outro skipping, and whether new
//  episodes queue themselves. Global settings stay the default; these only
//  override for shows that need it — the one that always opens with a two
//  minute sponsor read, or the one worth hearing at 1.5x when nothing else is.
//

import SwiftData
import SwiftUI

struct PodcastPlaybackSettingsView: View {
  let podcast: PodcastInfoModel
  let modelContext: ModelContext
  @Environment(\.dismiss) private var dismiss

  /// 0 means "no override" — presented as "Use Default" rather than "0x".
  @State private var speed: Float = 0
  @State private var skipIntroSeconds: Int = 0
  @State private var skipOutroSeconds: Int = 0
  @State private var autoAddToQueue: AutoAddToQueueSetting = .off

  private static let speedChoices: [Float] = [0, 0.8, 1.0, 1.2, 1.5, 1.75, 2.0]

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker("Speed", selection: $speed) {
            ForEach(Self.speedChoices, id: \.self) { choice in
              Text(choice == 0 ? "Use Default" : String(format: "%.2gx", choice))
                .tag(choice)
            }
          }
        } header: {
          Text("Playback speed")
        } footer: {
          Text("Overrides the global default speed for this show only. Changing it here never changes the global default.")
        }

        Section {
          Stepper("Skip first \(skipIntroSeconds)s", value: $skipIntroSeconds, in: 0...300, step: 5)
          Stepper("Skip last \(skipOutroSeconds)s", value: $skipOutroSeconds, in: 0...600, step: 5)
        } header: {
          Text("Skip intro and outro")
        } footer: {
          Text("Starts each new episode past the intro, and finishes it early past the outro. Resuming an episode you already started still returns you to where you left off.")
        }

        Section {
          Picker("New episodes", selection: $autoAddToQueue) {
            ForEach(AutoAddToQueueSetting.allCases, id: \.self) { setting in
              Text(setting.displayName).tag(setting)
            }
          }
        } header: {
          Text("Add to queue")
        } footer: {
          Text("Automatically add new episodes of this show to Up Next when they are found. Adding stops when the queue is full.")
        }
      }
      .navigationTitle("Playback")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            podcast.playbackSpeedOverride = speed
            podcast.skipIntroSeconds = skipIntroSeconds
            podcast.skipOutroSeconds = skipOutroSeconds
            podcast.autoAddToQueueSetting = autoAddToQueue.rawValue
            modelContext.saveOrLog()
            dismiss()
          }
        }
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .onAppear {
        // Snap a stored speed that isn't one of the offered choices onto the
        // nearest one, or the Picker would show a blank selection.
        speed = Self.speedChoices.contains(podcast.playbackSpeedOverride)
          ? podcast.playbackSpeedOverride
          : 0
        skipIntroSeconds = podcast.skipIntroSeconds
        skipOutroSeconds = podcast.skipOutroSeconds
        autoAddToQueue = AutoAddToQueueSetting(rawValue: podcast.autoAddToQueueSetting) ?? .off
      }
    }
  }
}
