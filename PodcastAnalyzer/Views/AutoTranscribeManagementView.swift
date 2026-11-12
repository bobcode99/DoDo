//
//  AutoTranscribeManagementView.swift
//  PodcastAnalyzer
//
//  Every automatic-transcription setting on one screen. There are two, and they
//  answer different questions:
//
//    - all podcasts  — transcribe whatever gets downloaded, whichever show
//    - per podcast   — follow these shows: use the feed's transcript when it
//                      has one, else the engine picked in Settings: Yap straight
//                      from the feed, on-device once the episode downloads
//
//  Both go through TranscriptManager.autoTranscribeDownload, and anything the
//  power gates skip is picked up by catchUpAutoTranscripts.
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
  @Bindable private var subtitleSettings = SubtitleSettingsManager.shared
  @State private var showDisableAllConfirmation = false
  @State private var backfill: BackfillRequest?

  private struct BackfillRequest: Identifiable {
    let podcast: PodcastInfoModel
    let offersNone: Bool
    var id: PersistentIdentifier { podcast.persistentModelID }
  }

  private var usesYap: Bool { TranscriptManager.defaultEngine == .yapServer }
  @State private var searchText: String = ""

  private var enabledPodcasts: [PodcastInfoModel] {
    filtered(subscribedPodcasts.filter { $0.autoTranscribeNewEpisodes })
  }

  private var otherPodcasts: [PodcastInfoModel] {
    filtered(subscribedPodcasts.filter { !$0.autoTranscribeNewEpisodes })
  }

  private func filtered(_ podcasts: [PodcastInfoModel]) -> [PodcastInfoModel] {
    let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return podcasts }
    return podcasts.filter { $0.title.localizedStandardContains(needle) }
  }

  var body: some View {
    List {
      Section {
        Toggle("Transcribe Downloads", isOn: $subtitleSettings.autoGenerateTranscripts)
      } header: {
        Text("All Podcasts")
      } footer: {
        Text("Every episode you download gets a transcript, whichever podcast it came from. On-device engines wait until this device is charging.")
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
            Text("New episodes use the show's own transcript when its feed has one. Otherwise, Yap transcribes them straight from the feed, and on-device engines transcribe them once downloaded, while charging.")
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
            ContentUnavailableView.search
          }
        }
      }
    }
    .searchable(text: $searchText, prompt: "Search podcasts")
    .sheet(item: $backfill) { request in
      TranscribeBackfillSheet(podcast: request.podcast.podcastInfo, offersNone: request.offersNone)
    }
    .navigationTitle("Automatic Transcription")
    .toolbar {
      if subscribedPodcasts.contains(where: { $0.autoTranscribeNewEpisodes }) {
        ToolbarItem(placement: .primaryAction) {
          Button("Stop All", role: .destructive) {
            showDisableAllConfirmation = true
          }
          .confirmationDialog(
            "Stop following \(subscribedPodcasts.count(where: \.autoTranscribeNewEpisodes)) podcasts?",
            isPresented: $showDisableAllConfirmation,
            titleVisibility: .visible
          ) {
            Button("Disable All", role: .destructive) {
              for podcast in subscribedPodcasts where podcast.autoTranscribeNewEpisodes {
                podcast.autoTranscribeNewEpisodes = false
              }
              modelContext.saveOrLog()
            }
            Button("Cancel", role: .cancel) { }
          } message: {
            Text("In-flight transcript jobs continue. Open the progress sheet to cancel them.")
          }
        }
      }
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
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.body)
          .lineLimit(1)
        Text(subtitle(
          enabled: enabled, pending: pending, episodes: podcast.episodeCount,
          waitsForManualDownloads: !usesYap && !podcast.downloadsNewEpisodes))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()

      Toggle(title, isOn: Binding(
        get: { podcast.autoTranscribeNewEpisodes },
        set: { newValue in
          podcast.autoTranscribeNewEpisodes = newValue
          modelContext.saveOrLog()
          if newValue { backfill = BackfillRequest(podcast: podcast, offersNone: true) }
        }
      ))
      .labelsHidden()
    }
    .contextMenu {
      Button("Transcribe Episodes…", systemImage: "waveform") {
        backfill = BackfillRequest(podcast: podcast, offersNone: false)
      }
    }
  }

  private func subtitle(
    enabled: Bool, pending: Int, episodes: Int, waitsForManualDownloads: Bool
  ) -> LocalizedStringKey {
    if enabled {
      if pending > 0 { return "\(pending) in progress" }
      // Without Yap or auto-download, new episodes only get a transcript
      // (beyond the feed's own) when the user downloads them.
      if waitsForManualDownloads { return "Transcribes episodes you download" }
      return "Listening for new episodes"
    }
    return "\(episodes) episodes"
  }

  private func activeCount(for podcastTitle: String) -> Int {
    syncManager.activeJobs.values.count { $0.podcastTitle == podcastTitle && $0.status.isInFlight }
  }
}
