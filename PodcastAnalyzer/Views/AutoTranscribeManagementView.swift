//
//  AutoTranscribeManagementView.swift
//  PodcastAnalyzer
//
//  Global overview of every podcast with auto-transcribe enabled, with a
//  one-tap disable per row and a "Disable all" bulk action.
//

import SwiftData
import SwiftUI

struct AutoTranscribeManagementView: View {
  @Environment(\.modelContext) private var modelContext

  @Query(
    filter: #Predicate<PodcastInfoModel> {
      $0.isSubscribed && $0.autoTranscribeNewEpisodes
    },
    sort: \.lastUpdated,
    order: .reverse
  ) private var enabledPodcasts: [PodcastInfoModel]

  @State private var syncManager = TranscriptManager.shared
  @State private var showDisableAllConfirmation = false

  var body: some View {
    Group {
      if enabledPodcasts.isEmpty {
        ContentUnavailableView(
          "No Auto-Transcribe Shows",
          systemImage: "waveform.slash",
          description: Text("Enable \"Auto-transcribe new episodes\" on any podcast's context menu, and it will appear here.")
        )
      } else {
        List {
          Section {
            ForEach(enabledPodcasts) { podcast in
              row(for: podcast)
            }
          } footer: {
            Text("New episodes from these podcasts are queued for transcription automatically. The engine is YAP server when configured, otherwise a local engine (gated by charging state).")
              .font(.footnote)
          }
        }
      }
    }
    .navigationTitle("Auto-transcribe")
    .toolbar {
      if !enabledPodcasts.isEmpty {
        ToolbarItem(placement: .primaryAction) {
          Button("Disable All", role: .destructive) {
            showDisableAllConfirmation = true
          }
        }
      }
    }
    .confirmationDialog(
      "Disable Auto-transcribe for \(enabledPodcasts.count) podcasts?",
      isPresented: $showDisableAllConfirmation,
      titleVisibility: .visible
    ) {
      Button("Disable All", role: .destructive) {
        for podcast in enabledPodcasts {
          podcast.autoTranscribeNewEpisodes = false
        }
        try? modelContext.save()
      }
      Button("Cancel", role: .cancel) { }
    } message: {
      Text("In-flight transcript jobs continue. Open the progress sheet to cancel them.")
    }
  }

  @ViewBuilder
  private func row(for podcast: PodcastInfoModel) -> some View {
    let title = podcast.podcastInfo.title
    let pending = activeCount(for: title)

    HStack(spacing: 12) {
      Image(systemName: "waveform.badge.plus")
        .foregroundStyle(.blue)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body)
          .lineLimit(1)
        if pending > 0 {
          Text("\(pending) in progress")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("Listening for new episodes")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()

      Toggle("", isOn: Binding(
        get: { podcast.autoTranscribeNewEpisodes },
        set: { newValue in
          podcast.autoTranscribeNewEpisodes = newValue
          try? modelContext.save()
        }
      ))
      .labelsHidden()
    }
  }

  private func activeCount(for podcastTitle: String) -> Int {
    syncManager.activeJobs.values.filter { job in
      guard job.podcastTitle == podcastTitle else { return false }
      switch job.status {
      case .queued, .downloadingModel, .transcribing: return true
      case .completed, .failed: return false
      }
    }.count
  }
}
