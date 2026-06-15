//
//  LibraryQuickAccessSection.swift
//  PodcastAnalyzer
//
//  Quick-access navigation cards at the top of the Library tab.
//  Extracted from LibraryView so SwiftUI can diff it independently.
//

import SwiftUI

struct LibraryQuickAccessSection: View {
  /// Observed directly so the high-churn episode counts (download progress,
  /// saved/downloaded changes) re-render only this card row instead of
  /// LibraryView.body and the whole podcast grid below it.
  let viewModel: LibraryViewModel

  @State private var showTranscriptProgressSheet = false

  var body: some View {
    let savedCount = viewModel.savedEpisodes.count
    let downloadedCount = viewModel.downloadedEpisodes.count + viewModel.downloadingEpisodes.count
    let latestCount = viewModel.latestEpisodes.count
    return VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        NavigationLink(value: LibrarySubpageRoute.saved) {
          QuickAccessCard(
            icon: "star.fill",
            iconColor: .yellow,
            title: "Saved",
            count: savedCount,
            isLoading: false
          )
        }
        .buttonStyle(.plain)

        NavigationLink(value: LibrarySubpageRoute.downloaded) {
          QuickAccessCard(
            icon: "arrow.down.circle.fill",
            iconColor: .green,
            title: "Downloaded",
            count: downloadedCount,
            isLoading: false
          )
        }
        .buttonStyle(.plain)
      }

      // Isolated subview observes TranscriptManager so progress ticks don't
      // invalidate the rest of LibraryQuickAccessSection on every update.
      TranscriptingCard(showSheet: $showTranscriptProgressSheet)

      NavigationLink(value: LibrarySubpageRoute.latest) {
        HStack {
          HStack(spacing: 8) {
            Image(systemName: "clock.fill")
              .font(.system(size: 16))
              .foregroundStyle(.blue)
            Text("Latest Episodes")
              .font(.subheadline)
              .fontWeight(.medium)
              .foregroundStyle(.primary)
          }

          Spacer()

          HStack(spacing: 4) {
            Text("\(latestCount)")
              .font(.caption)
              .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
      }
      .buttonStyle(.plain)
    }
    .sheet(isPresented: $showTranscriptProgressSheet) {
      TranscriptGenerationProgressOverallView()
    }
  }
}

// MARK: - Isolated transcribing card

/// Renders the "Transcribing N" card only when there are active jobs. Observing
/// `TranscriptManager.shared.activeJobs` inside this small view prevents progress
/// ticks from invalidating the parent section on every update.
private struct TranscriptingCard: View {
  @Binding var showSheet: Bool
  @State private var manager = TranscriptManager.shared

  private var activeCount: Int {
    var count = 0
    for job in manager.activeJobs.values {
      switch job.status {
      case .queued, .downloadingModel, .transcribing: count += 1
      case .completed, .failed: break
      }
    }
    return count
  }

  var body: some View {
    let count = activeCount
    if count > 0 {
      Button { showSheet = true } label: {
        HStack {
          HStack(spacing: 8) {
            Image(systemName: "waveform.badge.plus")
              .font(.system(size: 16))
              .foregroundStyle(.blue)
            Text("Transcribing")
              .font(.subheadline)
              .fontWeight(.medium)
              .foregroundStyle(.primary)
          }
          Spacer()
          HStack(spacing: 4) {
            ProgressView().scaleEffect(0.7)
            Text("\(count)")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
      }
      .buttonStyle(.plain)
    }
  }
}
