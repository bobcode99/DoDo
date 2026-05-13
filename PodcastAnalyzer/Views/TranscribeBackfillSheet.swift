//
//  TranscribeBackfillSheet.swift
//  PodcastAnalyzer
//
//  Shown when the user enables "Auto-transcribe new episodes" on a podcast.
//  Lets the user choose how far back to backfill, resolves the engine, and
//  enqueues jobs in TranscriptManager.
//

import SwiftUI

struct TranscribeBackfillSheet: View {
  let podcastTitle: String
  let podcastLanguage: String
  let episodes: [PodcastEpisodeInfo]

  @Environment(\.dismiss) private var dismiss

  @State private var selectedRange: BackfillRange = .none
  @State private var blockedReason: String?

  enum BackfillRange: String, CaseIterable, Identifiable {
    case none, last7, last30, all
    var id: String { rawValue }
    var label: String {
      switch self {
      case .none:   return "None — only future episodes"
      case .last7:  return "Last 7 days"
      case .last30: return "Last 30 days"
      case .all:    return "All episodes"
      }
    }
    var cutoff: Date? {
      switch self {
      case .none:   return Date.distantFuture     // matches nothing
      case .last7:  return Date(timeIntervalSinceNow: -7 * 24 * 3600)
      case .last30: return Date(timeIntervalSinceNow: -30 * 24 * 3600)
      case .all:    return Date.distantPast
      }
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Pick how many existing episodes to queue for transcription. New episodes that arrive in future feed refreshes are queued automatically.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        Section("Backfill range") {
          ForEach(BackfillRange.allCases) { range in
            Button { selectedRange = range } label: {
              HStack {
                Text(range.label)
                Spacer()
                Text("\(countForRange(range))")
                  .foregroundStyle(.secondary)
                  .monospacedDigit()
                if selectedRange == range {
                  Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                }
              }
              .contentShape(.rect)
            }
            .buttonStyle(.plain)
          }
        }

        if let reason = blockedReason {
          Section {
            VStack(alignment: .leading, spacing: 6) {
              Label("Local transcription uses significant battery", systemImage: "battery.25percent")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
              Text(reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
              Button("Continue this session") {
                TranscriptManager.shared.setAllowLocalOnBattery(true)
                blockedReason = nil
                confirm()
              }
              .buttonStyle(.borderedProminent)
              .controlSize(.small)
              .padding(.top, 4)
            }
            .padding(.vertical, 4)
          }
        }
      }
      .navigationTitle(podcastTitle)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Confirm") { confirm() }
        }
      }
    }
  }

  // MARK: - Helpers

  private func countForRange(_ range: BackfillRange) -> Int {
    guard let cutoff = range.cutoff, range != .none else { return 0 }
    return episodes.filter { ($0.pubDate ?? .distantPast) >= cutoff }.count
  }

  private func confirm() {
    let decision = TranscriptManager.shared.resolveAutoTranscribeEngine()
    if case .blocked(let reason) = decision {
      blockedReason = reason
      return
    }

    let cutoff = selectedRange.cutoff ?? .distantFuture
    let toQueue = episodes.filter { ($0.pubDate ?? .distantPast) >= cutoff }

    let engine: TranscriptEngine?
    switch decision {
    case .yap:               engine = .yapServer
    case .local(let local):  engine = local
    case .blocked:           return  // handled above
    }

    for ep in toQueue {
      guard !TranscriptManager.shared.isGenerating(
        episodeTitle: ep.title, podcastTitle: podcastTitle
      ) else { continue }

      TranscriptManager.shared.queueTranscript(
        episodeTitle: ep.title,
        podcastTitle: podcastTitle,
        audioPath: "",                       // YAP can use remote; local will fall back to .failed if no local file
        audioRemoteURL: ep.audioURL,
        language: podcastLanguage,
        engine: engine
      )
    }
    dismiss()
  }
}
