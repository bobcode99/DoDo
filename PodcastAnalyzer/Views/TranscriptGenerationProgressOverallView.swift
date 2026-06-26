//
//  TranscriptGenerationProgressOverallView.swift
//  PodcastAnalyzer
//
//  Live progress sheet for the global transcript queue. Reads only from
//  TranscriptManager.shared.activeJobs — no local state. Sections by status
//  with per-row cancel / retry and a "Cancel All" toolbar action.
//
//  Rows tap-navigate to EpisodeDetailView via TranscriptJobRoute resolved
//  through SwiftData. Heavy progress rows are split into TranscriptJobRow
//  subviews so each tick invalidates only the relevant row, not the whole list.
//

import SwiftData
import SwiftUI

struct TranscriptGenerationProgressOverallView: View {
  /// Wrap the contents in a NavigationStack? iOS presents this as a sheet so
  /// it needs its own stack; macOS embeds it as a sidebar destination inside
  /// the host stack and supplies the route registration itself.
  var embedNavigationStack: Bool = true

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
    if embedNavigationStack {
      NavigationStack {
        listContent
          .navigationDestination(for: TranscriptJobRoute.self) { route in
            TranscriptJobEpisodeDestination(route: route, onNavigated: { dismiss() })
          }
      }
    } else {
      listContent
    }
  }

  @ViewBuilder
  private var listContent: some View {
    List {
      if !active.isEmpty {
        Section("Active") {
          ForEach(active) { job in
            TranscriptJobRow(jobID: job.id, action: .cancel)
          }
        }
      }
      if !queued.isEmpty {
        Section("Queued") {
          ForEach(queued) { job in
            TranscriptJobRow(jobID: job.id, action: .cancel)
          }
        }
      }
      if !failed.isEmpty {
        Section("Failed") {
          ForEach(failed) { job in
            TranscriptJobRow(jobID: job.id, action: .retry)
          }
        }
      }
      if !completed.isEmpty {
        Section("Completed") {
          ForEach(completed) { job in
            TranscriptJobRow(jobID: job.id, action: .none)
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
      if embedNavigationStack {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") { dismiss() }
        }
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

// MARK: - Job Row (isolated observation)

/// Reads a single job from TranscriptManager.activeJobs by id, so progress
/// updates on one job re-render only this row instead of the whole list.
private struct TranscriptJobRow: View {
  let jobID: String
  let action: Action

  @State private var manager = TranscriptManager.shared

  enum Action { case cancel, retry, none }

  private var job: TranscriptJob? { manager.activeJobs[jobID] }

  var body: some View {
    if let job {
      NavigationLink(value: TranscriptJobRoute(
        podcastTitle: job.podcastTitle,
        episodeTitle: job.episodeTitle
      )) {
        content(for: job)
      }
    }
  }

  @ViewBuilder
  private func content(for job: TranscriptJob) -> some View {
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
      trailingControl(for: job)
    }
  }

  @ViewBuilder
  private func trailingControl(for job: TranscriptJob) -> some View {
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
        if let parts = job.partProgress {
          Text("Transcribing… \(Int(p * 100))% · part \(min(parts.completed + 1, parts.total))/\(parts.total)")
        } else {
          Text("Transcribing… \(Int(p * 100))%")
        }
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

// MARK: - Navigation Route

/// Lightweight route used inside the progress sheet's NavigationStack to push
/// EpisodeDetailView for a transcript job. The destination view resolves the
/// PodcastEpisodeInfo via a SwiftData fetch.
struct TranscriptJobRoute: Hashable {
  let podcastTitle: String
  let episodeTitle: String
}

/// Resolves a TranscriptJobRoute into the matching PodcastEpisodeInfo and
/// presents EpisodeDetailView. Falls back to a placeholder if the podcast or
/// episode can't be found (e.g., user unsubscribed mid-job).
struct TranscriptJobEpisodeBridgeView: View {
  let route: TranscriptJobRoute
  var body: some View {
    TranscriptJobEpisodeDestination(route: route)
  }
}

private struct TranscriptJobEpisodeDestination: View {
  let route: TranscriptJobRoute
  var onNavigated: (() -> Void)? = nil

  @Environment(\.modelContext) private var modelContext

  @Query private var podcasts: [PodcastInfoModel]

  init(route: TranscriptJobRoute, onNavigated: (() -> Void)? = nil) {
    self.route = route
    self.onNavigated = onNavigated
    let title = route.podcastTitle
    _podcasts = Query(filter: #Predicate<PodcastInfoModel> { $0.title == title })
  }

  var body: some View {
    if let podcast = podcasts.first,
       let episode = podcast.podcastInfo.episodes.first(where: { $0.title == route.episodeTitle }) {
      let lang = podcast.podcastInfo.language.isEmpty ? "en" : podcast.podcastInfo.language
      #if os(macOS)
      MacEpisodeDetailView(
        episode: episode,
        podcastTitle: podcast.podcastInfo.title,
        fallbackImageURL: podcast.podcastInfo.imageURL,
        podcastLanguage: lang
      )
      #else
      EpisodeDetailView(
        episode: episode,
        podcastTitle: podcast.podcastInfo.title,
        fallbackImageURL: podcast.podcastInfo.imageURL,
        podcastLanguage: lang
      )
      #endif
    } else {
      ContentUnavailableView(
        "Episode unavailable",
        systemImage: "questionmark.circle",
        description: Text("This episode is no longer available in your library.")
      )
    }
  }
}
