//
//  UpNextContextMenu.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/3/14.
//

import SwiftData
import SwiftUI

// MARK: - View

struct UpNextContextMenu: View {
  let episode: LibraryEpisode
  let isStarred: Bool
  let isCompleted: Bool
  let downloadState: DownloadState
  let podcastModel: PodcastInfoModel?
  let onToggleStar: () -> Void
  let onTogglePlayed: () -> Void
  let onPlayNext: () -> Void
  let onAddToQueue: () -> Void
  let onDownload: () -> Void
  let onCancelDownload: () -> Void
  let onDeleteDownload: () -> Void
  let onRetryDownload: () -> Void
  /// Optional "Remove from Queue". Non-nil only when this episode is actually
  /// in `EnhancedAudioManager.queue` — the caller decides, because the menu
  /// itself has no business observing the player.
  var onRemoveFromQueue: (() -> Void)? = nil
  /// Optional "Not Interested". Hides the episode from the Up Next
  /// *suggestions* without marking it played; replaying resurfaces it because
  /// `lastPlayedDate` overtakes `upNextDismissedAt`. Deliberately distinct
  /// from `onRemoveFromQueue`: this one never touches the play queue.
  var onDismissSuggestion: (() -> Void)? = nil

  var body: some View {
    goToShowSection
    starSection
    playedSection
    Divider()
    queueSection
    downloadSection
    Divider()
    shareSection
    removeSections
  }

  // MARK: - Go to Show

  @ViewBuilder
  private var goToShowSection: some View {
    if let podcastModel {
      NavigationLink(value: PodcastBrowseRoute(podcastModel: podcastModel)) {
        Label("Go to Show", systemImage: "square.stack")
      }

      Divider()
    }
  }

  // MARK: - Star

  private var starSection: some View {
    Button {
      onToggleStar()
    } label: {
      Label(
        isStarred ? "Unstar" : "Star",
        systemImage: isStarred ? "star.fill" : "star"
      )
    }
  }

  // MARK: - Played

  private var playedSection: some View {
    Button {
      onTogglePlayed()
    } label: {
      Label(
        isCompleted ? "Mark as Unplayed" : "Mark as Played",
        systemImage: isCompleted ? "arrow.counterclockwise" : "checkmark.circle"
      )
    }
  }

  // MARK: - Queue

  @ViewBuilder
  private var queueSection: some View {
    if episode.episodeInfo.audioURL != nil {
      Button {
        onPlayNext()
      } label: {
        Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
      }

      Button {
        onAddToQueue()
      } label: {
        Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
      }

      Divider()
    }
  }

  // MARK: - Download

  @ViewBuilder
  private var downloadSection: some View {
    switch downloadState {
    case .notDownloaded:
      Button {
        onDownload()
      } label: {
        Label("Download", systemImage: "arrow.down.circle")
      }

    case .downloading:
      Button {
        onCancelDownload()
      } label: {
        Label("Cancel Download", systemImage: "xmark.circle")
      }

    case .finishing:
      Label("Saving...", systemImage: "arrow.down.circle.dotted")

    case .downloaded:
      Button(role: .destructive) {
        onDeleteDownload()
      } label: {
        Label("Delete Download", systemImage: "trash")
      }

    case .failed:
      Button {
        onRetryDownload()
      } label: {
        Label("Retry Download", systemImage: "arrow.clockwise")
      }
    }
  }

  // MARK: - Share

  @ViewBuilder
  private var shareSection: some View {
    if let audioURL = episode.episodeInfo.audioURL, let url = URL(string: audioURL) {
      Button {
        PlatformShareSheet.share(url: url)
      } label: {
        Label("Share Episode", systemImage: "square.and.arrow.up")
      }
    }
  }

  // MARK: - Remove

  /// Two different removals, deliberately worded apart. "Remove from Queue"
  /// empties the episode out of the play queue; "Not Interested" only hides it
  /// from the scored suggestions. Conflating them under one "Remove from Up
  /// Next" label made the menu lie about which list it acted on.
  @ViewBuilder
  private var removeSections: some View {
    if onRemoveFromQueue != nil || onDismissSuggestion != nil {
      Divider()
    }

    if let onRemoveFromQueue {
      Button(role: .destructive, action: onRemoveFromQueue) {
        Label("Remove from Queue", systemImage: "text.badge.minus")
      }
    }

    if let onDismissSuggestion {
      Button(action: onDismissSuggestion) {
        Label("Not Interested", systemImage: "minus.circle")
      }
    }
  }
}

// MARK: - Preview

#Preview {
  let mockEpisode = LibraryEpisode(
    id: "preview_podcast\u{1F}preview_episode",
    podcastTitle: "The Swift Podcast",
    imageURL: nil,
    language: "en",
    episodeInfo: PodcastEpisodeInfo(
      title: "Understanding Swift Concurrency",
      podcastEpisodeDescription: "A deep dive into async/await",
      pubDate: Date(),
      audioURL: "https://example.com/episode.mp3",
      duration: 1800
    ),
    isStarred: true,
    isDownloaded: true,
    isCompleted: false,
    lastPlaybackPosition: 450,
    savedDuration: 1800
  )

  Menu("Long Press Me") {
    UpNextContextMenu(
      episode: mockEpisode,
      isStarred: true,
      isCompleted: false,
      downloadState: .downloaded(localPath: "/tmp/episode.mp3"),
      podcastModel: nil,
      onToggleStar: {},
      onTogglePlayed: {},
      onPlayNext: {},
      onAddToQueue: {},
      onDownload: {},
      onCancelDownload: {},
      onDeleteDownload: {},
      onRetryDownload: {}
    )
  }
  .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
