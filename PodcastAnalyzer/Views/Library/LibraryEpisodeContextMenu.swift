//
//  LibraryEpisodeContextMenu.swift
//  PodcastAnalyzer
//
//  Context menu for library episodes using closure/callback pattern.
//  All singleton calls are handled by the parent view.
//

import SwiftUI

struct LibraryEpisodeContextMenu: View {
  let episode: LibraryEpisode
  let isStarred: Bool
  let isCompleted: Bool
  let downloadState: DownloadState
  let podcastModel: PodcastInfoModel?
  let onPlay: () -> Void
  let onPlayNext: () -> Void
  let onToggleStar: () -> Void
  let onTogglePlayed: () -> Void
  let onDownload: () -> Void
  let onCancelDownload: () -> Void
  let onDeleteDownload: () -> Void
  let onShare: () -> Void

  var body: some View {
    goToShowSection
    Divider()
    playSection
    Divider()
    starSection
    playedSection
    Divider()
    downloadSection
    Divider()
    shareSection
  }

  // MARK: - Go to Show

  @ViewBuilder
  private var goToShowSection: some View {
    if let podcastModel {
      NavigationLink(value: PodcastBrowseRoute(podcastModel: podcastModel)) {
        Label("Go to Show", systemImage: "square.stack")
      }
    } else {
      Button {} label: {
        Label("Go to Show", systemImage: "square.stack")
      }
      .disabled(true)
    }
  }

  // MARK: - Play

  @ViewBuilder
  private var playSection: some View {
    Button(action: onPlay) {
      Label("Play Episode", systemImage: "play.fill")
    }
    .disabled(episode.episodeInfo.audioURL == nil)

    Button(action: onPlayNext) {
      Label("Play Next", systemImage: "text.insert")
    }
    .disabled(episode.episodeInfo.audioURL == nil)
  }

  // MARK: - Star

  private var starSection: some View {
    Button(action: onToggleStar) {
      Label(
        isStarred ? "Remove from Saved" : "Save Episode",
        systemImage: isStarred ? "star.slash" : "star"
      )
    }
  }

  // MARK: - Played

  private var playedSection: some View {
    Button(action: onTogglePlayed) {
      Label(
        isCompleted ? "Mark as Unplayed" : "Mark as Played",
        systemImage: isCompleted ? "arrow.counterclockwise" : "checkmark.circle"
      )
    }
  }

  // MARK: - Download

  @ViewBuilder
  private var downloadSection: some View {
    switch downloadState {
    case .downloaded:
      Button(role: .destructive, action: onDeleteDownload) {
        Label("Delete Download", systemImage: "trash")
      }
    case .downloading:
      Button(action: onCancelDownload) {
        Label("Cancel Download", systemImage: "xmark.circle")
      }
    case .finishing:
      Label("Saving...", systemImage: "arrow.down.circle.dotted")
    case .failed:
      Button(action: onDownload) {
        Label("Retry Download", systemImage: "arrow.clockwise")
      }
    case .notDownloaded:
      if episode.episodeInfo.audioURL != nil {
        Button(action: onDownload) {
          Label("Download", systemImage: "arrow.down.circle")
        }
      }
    }
  }

  // MARK: - Share

  @ViewBuilder
  private var shareSection: some View {
    if let audioURL = episode.episodeInfo.audioURL, URL(string: audioURL) != nil {
      Button(action: onShare) {
        Label("Share", systemImage: "square.and.arrow.up")
      }
    }
  }
}
