//
//  EpisodeStatusIcons.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/4.
//

import Foundation
import SwiftUI

/// Reusable view for displaying episode status icons
/// Use isCompact: true for overlays on artwork (smaller icons with background)
struct EpisodeStatusIcons: View {
  let isStarred: Bool
  let isDownloaded: Bool
  let hasTranscript: Bool
  let hasAIAnalysis: Bool
  let isCompleted: Bool
  let showCompleted: Bool
  let isDownloading: Bool
  let downloadProgress: Double
  let isTranscribing: Bool
  let isCompact: Bool
  /// When set, the downloading ring live-polls this episode's in-flight
  /// progress instead of relying on `downloadProgress` snapshots.
  let episodeKey: String?

  init(
    isStarred: Bool = false,
    isDownloaded: Bool = false,
    hasTranscript: Bool = false,
    hasAIAnalysis: Bool = false,
    isCompleted: Bool = false,
    showCompleted: Bool = true,
    isDownloading: Bool = false,
    downloadProgress: Double = 0,
    isTranscribing: Bool = false,
    isCompact: Bool = false,
    episodeKey: String? = nil
  ) {
    self.isStarred = isStarred
    self.isDownloaded = isDownloaded
    self.hasTranscript = hasTranscript
    self.hasAIAnalysis = hasAIAnalysis
    self.isCompleted = isCompleted
    self.showCompleted = showCompleted
    self.isDownloading = isDownloading
    self.downloadProgress = downloadProgress
    self.isTranscribing = isTranscribing
    self.isCompact = isCompact
    self.episodeKey = episodeKey
  }

  private var hasAnyStatus: Bool {
    isStarred || isDownloaded || hasTranscript || hasAIAnalysis || isDownloading || isTranscribing || (showCompleted && isCompleted)
  }

  // Icon sizes based on compact mode
  private var iconSize: CGFloat { isCompact ? 9 : 10 }
  private var spacing: CGFloat { isCompact ? 3 : 4 }
  private var progressFrameSize: CGFloat { 14 }
  private var transcriptIconSize: CGFloat { isCompact ? 7 : 8 }

  var body: some View {
    if isCompact {
      compactBody
    } else {
      standardBody
    }
  }

  private var standardBody: some View {
    HStack(spacing: spacing) {
      if isStarred {
        statusIcon("star.fill", color: .yellow)
      }

      // Download status: show progress if downloading, icon if downloaded
      if isDownloading {
        downloadProgressView
      } else if isDownloaded {
        statusIcon("arrow.down.circle.fill", color: .green)
      }

      // Transcript status: show progress if transcribing, icon if has transcript
      if isTranscribing {
        transcriptProgressView
      } else if hasTranscript {
        statusIcon("captions.bubble.fill", color: .purple)
      }

      if hasAIAnalysis {
        statusIcon("sparkles", color: .orange)
      }

      if showCompleted && isCompleted {
        statusIcon("checkmark.circle.fill", color: .green)
      }
    }
  }

  @ViewBuilder
  private var compactBody: some View {
    if hasAnyStatus {
      HStack(spacing: spacing) {
        if isStarred {
          statusIcon("star.fill", color: .yellow)
        }

        // Download status: show progress if downloading, checkmark if downloaded
        if isDownloading {
          downloadProgressView
        } else if isDownloaded {
          statusIcon("arrow.down.circle.fill", color: .green)
        }

        // Transcript status: show progress if transcribing, icon if has transcript
        if isTranscribing {
          transcriptProgressView
        } else if hasTranscript {
          statusIcon("captions.bubble.fill", color: .purple)
        }

        if hasAIAnalysis {
          statusIcon("sparkles", color: .orange)
        }
      }
      .padding(4)
      .background(.ultraThinMaterial)
      .clipShape(.rect(cornerRadius: 6))
      .padding(4)
    }
  }

  private func statusIcon(_ name: String, color: Color) -> some View {
    Image(systemName: name)
      .font(.system(size: iconSize, weight: isCompact ? .bold : .regular))
      .foregroundStyle(color)
  }

  @ViewBuilder
  private var downloadProgressView: some View {
    // Live ring when the caller supplies the episode key — keeps the ring
    // current without the caller having to observe progress ticks. Falls back
    // to the passed-in snapshot value otherwise.
    if let episodeKey {
      LiveDownloadProgressRing(episodeKey: episodeKey, size: progressFrameSize, symbol: "arrow.down")
    } else {
      DownloadProgressRing(progress: downloadProgress, size: progressFrameSize, symbol: "arrow.down")
    }
  }

  private var transcriptProgressView: some View {
    HStack(spacing: 2) {
      ProgressView()
        .scaleEffect(0.4)
        .frame(width: 10, height: 10)
      Image(systemName: "text.bubble")
        .font(.system(size: transcriptIconSize, weight: .bold))
        .foregroundStyle(.purple)
    }
  }
}

