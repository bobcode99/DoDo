//
//  AutoTranscribeManagementView.swift
//  PodcastAnalyzer
//
//  Every automatic-transcription setting on one screen. There are two, and they
//  used to sit in different Settings sections under names that did not
//  distinguish them ("Auto-Generate Transcripts" vs "Auto-transcribe
//  Podcasts"). They answer different questions:
//
//    - all podcasts  — transcribe whatever gets downloaded, whichever show
//    - per podcast   — follow these shows, and with a Yap server transcribe
//                      new episodes straight from the feed, no download needed
//
//  Showing them adjacent, with footers that name the trigger, is the fix.
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
    return podcasts.filter { $0.title.lowercased().contains(needle) }
  }

  var body: some View {
    List {
      Section {
        Toggle(isOn: Binding(
          get: { SubtitleSettingsManager.shared.autoGenerateTranscripts },
          set: { SubtitleSettingsManager.shared.autoGenerateTranscripts = $0 }
        )) {
          Text("Transcribe Downloads")
        }
      } header: {
        Text("All Podcasts")
      } footer: {
        Text("Every episode you download gets a transcript, whichever podcast it came from.")
      }

      if subscribedPodcasts.isEmpty {
        Section {
          ContentUnavailableView(
            "No Subscribed Podcasts",
            systemImage: "rectangle.stack.badge.person.crop",
            description: Text("Subscribe to a podcast to follow it here.")
          )
        }
      } else {
        if !enabledPodcasts.isEmpty {
          Section {
            ForEach(enabledPodcasts) { podcast in
              row(for: podcast)
            }
          } header: {
            Text("Following (\(enabledPodcasts.count))")
          } footer: {
            Text("New episodes are transcribed as soon as they appear — with a Yap server no download is needed, otherwise the episode is transcribed on device once downloaded and charging.")
              .font(.footnote)
          }
        }

        if !otherPodcasts.isEmpty {
          Section {
            ForEach(otherPodcasts) { podcast in
              row(for: podcast)
            }
          } header: {
            Text("Not Following (\(otherPodcasts.count))")
          } footer: {
            if enabledPodcasts.isEmpty {
              Text("Turn on a podcast to transcribe its new episodes automatically.")
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
    }
    .searchable(text: $searchText, prompt: "Search podcasts")
    .navigationTitle("Automatic Transcription")
    .toolbar {
      if !subscribedPodcasts.filter({ $0.autoTranscribeNewEpisodes }).isEmpty {
        ToolbarItem(placement: .primaryAction) {
          Button("Stop All", role: .destructive) {
            showDisableAllConfirmation = true
          }
        }
      }
    }
    .confirmationDialog(
      "Stop following \(subscribedPodcasts.filter({ $0.autoTranscribeNewEpisodes }).count) podcasts?",
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
    let title = podcast.title
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
        Text(subtitle(enabled: enabled, pending: pending, episodes: podcast.episodeCount))
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
