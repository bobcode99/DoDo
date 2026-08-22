//
//  EpisodeMenuActions.swift
//  PodcastAnalyzer
//
//  Shared menu actions for episode ellipsis menus - used by both EpisodeListView and EpisodeDetailView
//

import SwiftUI

/// Shared menu content for episode actions - ensures consistent behavior across EpisodeListView and EpisodeDetailView
struct EpisodeMenuActions: View {
  let isStarred: Bool
  let isCompleted: Bool
  let hasLocalAudio: Bool
  let downloadState: DownloadState
  let audioURL: String?

  let onToggleStar: () -> Void
  let onTogglePlayed: () -> Void
  let onDownload: () -> Void
  let onCancelDownload: () -> Void
  let onDeleteDownload: () -> Void
  let onShare: () -> Void
  var onPlayNext: (() -> Void)? = nil
  var onAddToQueue: (() -> Void)? = nil
  /// Apple-Podcasts-style "Remove from Up Next". When non-nil the menu appends
  /// a destructive remove button after Share. Only the Up Next list passes
  /// this closure — other call sites leave it nil.
  var onRemoveFromUpNext: (() -> Void)? = nil

  // For Apple Podcast URL sharing
  var episodeTitle: String? = nil
  var podcastCollectionId: Int? = nil

  var body: some View {
    // Star/Unstar
    Button(action: onToggleStar) {
      Label(
        isStarred ? "Unstar" : "Star",
        systemImage: isStarred ? "star.fill" : "star"
      )
    }

    // Mark as Played/Unplayed
    Button(action: onTogglePlayed) {
      Label(
        isCompleted ? "Mark as Unplayed" : "Mark as Played",
        systemImage: isCompleted ? "arrow.counterclockwise" : "checkmark.circle"
      )
    }

    Divider()

    // Queue options
    if audioURL != nil, onPlayNext != nil || onAddToQueue != nil {
      if let onPlayNext {
        Button(action: onPlayNext) {
          Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
        }
      }

      if let onAddToQueue {
        Button(action: onAddToQueue) {
          Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
        }
      }

      Divider()
    }

    // Download actions based on state
    downloadActions

    Divider()

    // Share action
    if audioURL != nil {
      Button(action: onShare) {
        Label("Share Episode", systemImage: "square.and.arrow.up")
      }
    }

    if let onRemoveFromUpNext {
      Divider()
      Button(role: .destructive, action: onRemoveFromUpNext) {
        Label("Remove from Up Next", systemImage: "text.badge.minus")
      }
    }
  }

  @ViewBuilder
  private var downloadActions: some View {
    switch downloadState {
    case .notDownloaded:
      Button(action: onDownload) {
        Label("Download", systemImage: "arrow.down.circle")
      }
      .disabled(audioURL == nil)

    case .downloading:
      Button(action: onCancelDownload) {
        Label("Cancel Download", systemImage: "xmark.circle")
      }

    case .finishing:
      Label("Saving...", systemImage: "arrow.down.circle.dotted")

    case .downloaded:
      Button(role: .destructive, action: onDeleteDownload) {
        Label("Delete Download", systemImage: "trash")
      }

    case .failed:
      Button(action: onDownload) {
        Label("Retry Download", systemImage: "arrow.clockwise")
      }
    }
  }
}
