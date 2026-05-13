//
//  TranscriptGenerationProgressOverallView.swift
//  PodcastAnalyzer
//
//  Live progress sheet for the global transcript queue. Reads only from
//  TranscriptManager.shared.activeJobs — no local state. Sections by status
//  with per-row cancel / retry and a "Cancel All" toolbar action.
//

import SwiftUI

struct TranscriptGenerationProgressOverallView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var manager = TranscriptManager.shared

  private var active: [TranscriptJob] {
    manager.activeJobs.values.filter {
      switch $0.status {
      case .transcribing, .downloadingModel: return true
      default: return false
      }
    }.sorted(by: { $0.episodeTitle < $1.episodeTitle })
  }

  private var queued: [TranscriptJob] {
    manager.activeJobs.values.filter {
      if case .queued = $0.status { return true }
      return false
    }.sorted(by: { $0.episodeTitle < $1.episodeTitle })
  }

  private var failed: [TranscriptJob] {
    manager.activeJobs.values.filter {
      if case .failed = $0.status { return true }
      return false
    }.sorted(by: { $0.episodeTitle < $1.episodeTitle })
  }

  private var completed: [TranscriptJob] {
    manager.activeJobs.values.filter {
      if case .completed = $0.status { return true }
      return false
    }.sorted(by: { $0.episodeTitle < $1.episodeTitle })
  }

  var body: some View {
    NavigationStack {
      List {
        if !active.isEmpty {
          Section("Active") {
            ForEach(active) { job in
              row(for: job, action: .cancel)
            }
          }
        }
        if !queued.isEmpty {
          Section("Queued") {
            ForEach(queued) { job in
              row(for: job, action: .cancel)
            }
          }
        }
        if !failed.isEmpty {
          Section("Failed") {
            ForEach(failed) { job in
              row(for: job, action: .retry)
            }
          }
        }
        if !completed.isEmpty {
          Section("Completed") {
            ForEach(completed) { job in
              row(for: job, action: .none)
            }
          }
        }
        if manager.activeJobs.isEmpty {
          ContentUnavailableView(
            "Nothing in the queue",
            systemImage: "waveform",
            description: Text("Transcript jobs you start will appear here with live progress.")
          )
        }
      }
      .navigationTitle("Transcription")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
        if !active.isEmpty || !queued.isEmpty {
          ToolbarItem(placement: .primaryAction) {
            Button("Cancel All", role: .destructive) {
              manager.cancelAll()
            }
          }
        }
      }
    }
  }

  enum RowAction { case cancel, retry, none }

  @ViewBuilder
  private func row(for job: TranscriptJob, action: RowAction) -> some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(job.episodeTitle)
          .font(.subheadline)
          .lineLimit(1)
        Text(job.podcastTitle)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        statusLine(for: job)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      switch action {
      case .cancel:
        Button {
          manager.cancelJob(episodeTitle: job.episodeTitle, podcastTitle: job.podcastTitle)
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
      case .retry:
        Button {
          manager.queueTranscript(
            episodeTitle: job.episodeTitle,
            podcastTitle: job.podcastTitle,
            audioPath: job.audioPath,
            audioRemoteURL: job.audioRemoteURL,
            language: job.language,
            engine: job.engine
          )
        } label: {
          Image(systemName: "arrow.clockwise.circle.fill")
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
      case .none:
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }
    }
  }

  @ViewBuilder
  private func statusLine(for job: TranscriptJob) -> some View {
    switch job.status {
    case .queued:
      Text("Waiting")
    case .downloadingModel(let p):
      ProgressView(value: p) {
        Text("Downloading model… \(Int(p * 100))%")
      }
    case .transcribing(let p):
      ProgressView(value: p) {
        Text("Transcribing… \(Int(p * 100))%")
      }
    case .completed:
      Text("Done")
    case .failed(let err):
      Text(err)
        .foregroundStyle(.red)
        .lineLimit(2)
    }
  }
}
