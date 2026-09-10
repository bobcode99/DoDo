//
//  PodcastContextMenu.swift
//  PodcastAnalyzer
//
//  Reusable context menu for podcast grid cells (Library, Downloads, etc.).
//

import SwiftData
import SwiftUI

struct PodcastContextMenu: ViewModifier {
  // @Bindable, not `let`: PodcastInfoModel is an @Model and therefore already
  // Observable, so its properties vend bindings directly. The hand-rolled
  // Binding(get:set:) this replaces was rebuilt on every evaluation of this
  // modifier — 3,406 of them in library-timeprofile-0829.trace.
  @Bindable var podcast: PodcastInfoModel
  let modelContext: ModelContext
  var onError: ((String) -> Void)?
  var onUnsubscribed: (() -> Void)?

  @State private var showUnsubscribeConfirmation = false
  @State private var showEpisodeFilterSheet = false
  @State private var showPlaybackSettingsSheet = false
  @State private var showTranscribeBackfillSheet = false

  func body(content: Content) -> some View {
    content
      .contextMenu {
        NavigationLink(value: PodcastBrowseRoute(podcastModel: podcast)) {
          Label("View Episodes", systemImage: "list.bullet")
        }

        Divider()

        Button {
          Task {
            await refreshPodcast()
          }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }

        Button {
          PlatformClipboard.string = podcast.rssUrl
        } label: {
          Label("Copy RSS URL", systemImage: "doc.on.doc")
        }

        Divider()

        // Auto-transcribe new episodes — engine resolved at run time (YAP → local).
        Toggle(isOn: $podcast.autoTranscribeNewEpisodes) {
          Label("Auto-transcribe new episodes", systemImage: "waveform.badge.plus")
        }

        // Three-state auto-download setting (AntennaPod pattern)
        Menu {
          ForEach(AutoDownloadSetting.allCases, id: \.rawValue) { setting in
            Button {
              podcast.autoDownloadSetting = setting.rawValue
              modelContext.saveOrLog()
            } label: {
              // Branch rather than passing "" as the systemImage: Label always
              // builds an Image(systemName:), so the empty string is a real
              // lookup that SF Symbols logs as a miss on every unselected row.
              if podcast.autoDownloadSetting == setting.rawValue {
                Label(setting.displayName, systemImage: "checkmark")
              } else {
                Text(setting.displayName)
              }
            }
          }
        } label: {
          Label(
            "Auto Download: \(AutoDownloadSetting(rawValue: podcast.autoDownloadSetting)?.displayName ?? "—")",
            systemImage: "arrow.down.circle"
          )
        }

        Button {
          showEpisodeFilterSheet = true
        } label: {
          Label("Episode Filter…", systemImage: "line.3.horizontal.decrease.circle")
        }

        Button {
          showPlaybackSettingsSheet = true
        } label: {
          Label("Playback…", systemImage: "speedometer")
        }

        Divider()

        Button(role: .destructive) {
          showUnsubscribeConfirmation = true
        } label: {
          Label("Unsubscribe", systemImage: "minus.circle")
        }
      }
      .onChange(of: podcast.autoTranscribeNewEpisodes) { _, isOn in
        modelContext.saveOrLog()
        // Offer to backfill only when switching on, not when switching off.
        if isOn { showTranscribeBackfillSheet = true }
      }
      .sheet(isPresented: $showEpisodeFilterSheet) {
        PodcastEpisodeFilterView(podcast: podcast, modelContext: modelContext)
      }
      .sheet(isPresented: $showPlaybackSettingsSheet) {
        PodcastPlaybackSettingsView(podcast: podcast, modelContext: modelContext)
      }
      .sheet(isPresented: $showTranscribeBackfillSheet) {
        TranscribeBackfillSheet(
          podcastTitle: podcast.podcastInfo.title,
          podcastLanguage: podcast.podcastInfo.language,
          episodes: podcast.podcastInfo.episodes
        )
      }
      .confirmationDialog(
        "Unsubscribe from Podcast",
        isPresented: $showUnsubscribeConfirmation,
        titleVisibility: .visible
      ) {
        Button("Unsubscribe", role: .destructive) {
          unsubscribePodcast()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        // `podcast.title`, not `podcast.podcastInfo.title`: this message closure is
        // non-escaping, so it is built on every render of every grid cell — and
        // reading the blob there decodes the whole episode array each time.
        Text("Are you sure you want to unsubscribe from \"\(podcast.title)\"? Downloaded episodes will remain available.")
      }
  }

  private func refreshPodcast() async {
    let rssService = PodcastRssService()
    do {
      let updatedPodcast = try await rssService.fetchPodcast(from: podcast.rssUrl)
      podcast.applyPodcastInfo(updatedPodcast)
      podcast.lastUpdated = Date()
      try modelContext.save()
    } catch {
      onError?("Failed to refresh: \(error.localizedDescription)")
    }
  }

  private func unsubscribePodcast() {
    podcast.setSubscribed(false)
    do {
      try modelContext.save()
      onUnsubscribed?()
    } catch {
      onError?("Failed to unsubscribe: \(error.localizedDescription)")
    }
  }
}

extension View {
  func podcastContextMenu(
    podcast: PodcastInfoModel,
    modelContext: ModelContext,
    onError: ((String) -> Void)? = nil,
    onUnsubscribed: (() -> Void)? = nil
  ) -> some View {
    modifier(PodcastContextMenu(
      podcast: podcast,
      modelContext: modelContext,
      onError: onError,
      onUnsubscribed: onUnsubscribed
    ))
  }
}
