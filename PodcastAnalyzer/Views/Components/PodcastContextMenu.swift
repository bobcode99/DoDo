//
//  PodcastContextMenu.swift
//  PodcastAnalyzer
//
//  Reusable context menu for podcast grid cells (Library, Downloads, etc.).
//

import SwiftData
import SwiftUI

struct PodcastContextMenu: ViewModifier {
  let podcast: PodcastInfoModel
  let modelContext: ModelContext
  var onError: ((String) -> Void)?
  var onUnsubscribed: (() -> Void)?

  @State private var showUnsubscribeConfirmation = false
  @State private var showEpisodeFilterSheet = false

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
          PlatformClipboard.string = podcast.podcastInfo.rssUrl
        } label: {
          Label("Copy RSS URL", systemImage: "doc.on.doc")
        }

        Divider()

        // Auto-transcript via Yap server (only shown when a server URL is configured)
        if !YapServerSettings.shared.serverURL.isEmpty {
          Toggle(isOn: Binding(
            get: { podcast.autoTranscribeWithYap },
            set: { newValue in
              podcast.autoTranscribeWithYap = newValue
              try? modelContext.save()
            }
          )) {
            Label("Auto Transcript (Yap)", systemImage: "waveform.badge.plus")
          }
        }

        // Three-state auto-download setting (AntennaPod pattern)
        Menu {
          ForEach(AutoDownloadSetting.allCases, id: \.rawValue) { setting in
            Button {
              podcast.autoDownloadSetting = setting.rawValue
              try? modelContext.save()
            } label: {
              Label(
                setting.displayName,
                systemImage: podcast.autoDownloadSetting == setting.rawValue ? "checkmark" : ""
              )
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

        Divider()

        Button(role: .destructive) {
          showUnsubscribeConfirmation = true
        } label: {
          Label("Unsubscribe", systemImage: "minus.circle")
        }
      }
      .sheet(isPresented: $showEpisodeFilterSheet) {
        PodcastEpisodeFilterView(podcast: podcast, modelContext: modelContext)
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
        Text("Are you sure you want to unsubscribe from \"\(podcast.podcastInfo.title)\"? Downloaded episodes will remain available.")
      }
  }

  private func refreshPodcast() async {
    let rssService = PodcastRssService()
    do {
      let updatedPodcast = try await rssService.fetchPodcast(from: podcast.podcastInfo.rssUrl)
      podcast.podcastInfo = updatedPodcast
      podcast.lastUpdated = Date()
      try modelContext.save()
    } catch {
      onError?("Failed to refresh: \(error.localizedDescription)")
    }
  }

  private func unsubscribePodcast() {
    podcast.isSubscribed = false
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
