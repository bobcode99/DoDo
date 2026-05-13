//
//  LibraryQuickAccessSection.swift
//  PodcastAnalyzer
//
//  Quick-access navigation cards at the top of the Library tab.
//  Extracted from LibraryView so SwiftUI can diff it independently.
//

import SwiftUI

struct LibraryQuickAccessSection: View {
  let savedCount: Int
  let downloadedCount: Int
  let latestCount: Int

  @State private var transcriptManager = TranscriptManager.shared
  @State private var showTranscriptProgressSheet = false

  private var activeTranscriptCount: Int {
    transcriptManager.activeJobs.values.filter { job in
      switch job.status {
      case .queued, .downloadingModel, .transcribing: return true
      case .completed, .failed: return false
      }
    }.count
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
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

      if activeTranscriptCount > 0 {
        Button { showTranscriptProgressSheet = true } label: {
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
              Text("\(activeTranscriptCount)")
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
