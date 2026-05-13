//
//  AutoTranscribeManagementView.swift
//  PodcastAnalyzer
//
//  Central overview of every subscribed podcast. The first section lists shows
//  with auto-transcribe enabled (with disable / bulk-disable), and the second
//  section lists the rest so users can flip the feature on from one place.
//

import SwiftData
import SwiftUI

struct AutoTranscribeManagementView: View {
  @Environment(\.modelContext) private var modelContext

  @Query(
    filter: #Predicate<PodcastInfoModel> { $0.isSubscribed },
    sort: \.lastUpdated,
    order: .reverse
  ) private var subscribedPodcasts: [PodcastInfoModel]

  @State private var syncManager = TranscriptManager.shared
  @State private var showDisableAllConfirmation = false
  @State private var searchText: String = ""

  private var enabledPodcasts: [PodcastInfoModel] {
    filtered(subscribedPodcasts.filter { $0.autoTranscribeNewEpisodes })
  }

  private var otherPodcasts: [PodcastInfoModel] {
    filtered(subscribedPodcasts.filter { !$0.autoTranscribeNewEpisodes })
  }

  private func filtered(_ podcasts: [PodcastInfoModel]) -> [PodcastInfoModel] {
    let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !needle.isEmpty else { return podcasts }
    return podcasts.filter { $0.podcastInfo.title.lowercased().contains(needle) }
  }

  var body: some View {
    Group {
      if subscribedPodcasts.isEmpty {
        ContentUnavailableView(
          "No Subscribed Podcasts",
          systemImage: "rectangle.stack.badge.person.crop",
          description: Text("Subscribe to a podcast to manage auto-transcribe from here.")
        )
      } else {
        List {
          if !enabledPodcasts.isEmpty {
            Section {
              ForEach(enabledPodcasts) { podcast in
                row(for: podcast)
              }
            } header: {
              Text("Auto-transcribe On (\(enabledPodcasts.count))")
            } footer: {
              Text("New episodes from these podcasts are queued for transcription automatically. The engine is YAP server when configured, otherwise a local engine (gated by charging state).")
                .font(.footnote)
            }
          }

          if !otherPodcasts.isEmpty {
            Section {
              ForEach(otherPodcasts) { podcast in
                row(for: podcast)
              }
            } header: {
              Text("Other Subscribed (\(otherPodcasts.count))")
            } footer: {
              if enabledPodcasts.isEmpty {
                Text("Tap any toggle to start auto-transcribing a podcast's new episodes.")
                  .font(.footnote)
              }
            }
          }

          if enabledPodcasts.isEmpty && otherPodcasts.isEmpty {
            Section {
              ContentUnavailableView.search(text: searchText)
            }
          }
        }
        .searchable(text: $searchText, prompt: "Search podcasts")
      }
    }
    .navigationTitle("Auto-transcribe")
    .toolbar {
      if !subscribedPodcasts.filter({ $0.autoTranscribeNewEpisodes }).isEmpty {
        ToolbarItem(placement: .primaryAction) {
          Button("Disable All", role: .destructive) {
            showDisableAllConfirmation = true
          }
        }
      }
    }
    .confirmationDialog(
      "Disable Auto-transcribe for \(subscribedPodcasts.filter({ $0.autoTranscribeNewEpisodes }).count) podcasts?",
      isPresented: $showDisableAllConfirmation,
      titleVisibility: .visible
    ) {
      Button("Disable All", role: .destructive) {
        for podcast in subscribedPodcasts where podcast.autoTranscribeNewEpisodes {
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
    let enabled = podcast.autoTranscribeNewEpisodes
    let pending = activeCount(for: title)

    HStack(spacing: 12) {
      Image(systemName: enabled ? "waveform.badge.plus" : "waveform")
        .foregroundStyle(enabled ? .blue : .secondary)
        .frame(width: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body)
          .lineLimit(1)
        Text(subtitle(enabled: enabled, pending: pending, episodes: podcast.podcastInfo.episodes.count))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
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

  private func subtitle(enabled: Bool, pending: Int, episodes: Int) -> String {
    if enabled {
      if pending > 0 { return "\(pending) in progress" }
      return "Listening for new episodes"
    }
    return "\(episodes) episode\(episodes == 1 ? "" : "s")"
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
