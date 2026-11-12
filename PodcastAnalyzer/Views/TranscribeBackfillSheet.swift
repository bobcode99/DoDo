//
//  TranscribeBackfillSheet.swift
//  PodcastAnalyzer
//
//  Queues transcripts for several episodes at once: a show's latest episodes
//  (from the show menu, or right after "Auto-transcribe new episodes" is
//  switched on) or the Up Next list. Resolves the engine and hands the
//  episodes to TranscriptManager.queueBatch.
//

import SwiftUI

struct TranscribeBackfillSheet: View {
  let title: String
  /// Highest priority first: newest for a show, list order for Up Next.
  let items: [BatchTranscriptItem]
  var order: Order = .newest
  /// Adds "None — only future episodes", for when auto-transcribe was just enabled.
  var offersNone = false

  enum Order { case newest, upNext }

  @Environment(\.dismiss) private var dismiss

  @State private var limit: Int?
  @State private var needsTranscript: [Bool] = []
  @State private var blockedReason: String?

  /// How many of `items` to queue: 0 = none, `items.count` = all.
  private var presets: [Int] {
    (offersNone ? [0] : []) + [5, 10, 25].filter { $0 < items.count } + [items.count]
  }

  private var selectedLimit: Int {
    limit ?? (offersNone ? 0 : min(10, items.count))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(offersNone
            ? "Pick how many existing episodes to queue for transcription. New episodes that arrive in future feed refreshes are queued automatically."
            : "Episodes that already have a transcript are skipped, and a show's own transcript is used when its feed has one. On-device engines download episodes first.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }

        Section("Episodes") {
          ForEach(presets, id: \.self) { preset in
            Button { limit = preset } label: {
              HStack {
                Text(label(for: preset))
                Spacer()
                Text("\(toQueueCount(preset))")
                  .foregroundStyle(.secondary)
                  .monospacedDigit()
                if selectedLimit == preset {
                  Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                }
              }
              .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedLimit == preset ? .isSelected : [])
          }
        }

        // Shown up front, so tapping Transcribe means "run on battery anyway".
        if let reason = blockedReason {
          Section {
            VStack(alignment: .leading, spacing: 6) {
              Label("Local transcription uses significant battery", systemImage: "battery.25percent")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
              Text("\(reason) Plug in to save battery, or tap Transcribe to start anyway.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
          }
        }
      }
      .navigationTitle(title)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(offersNone ? "Confirm" : "Transcribe") { confirm() }
            .disabled(!offersNone && toQueueCount(selectedLimit) == 0)
        }
      }
      .onAppear {
        if case .blocked(let reason) = TranscriptManager.shared.resolveAutoTranscribeEngine() {
          blockedReason = reason
        }
        // One transcript fetch for the whole list, not one per row per render.
        let existing = TranscriptStore.shared.existingEpisodeIds()
        needsTranscript = items.map { item in
          !existing.contains(EpisodeKeyUtils.makeKey(
            podcastTitle: item.podcastTitle, episodeTitle: item.episode.title))
            && !TranscriptManager.shared.isGenerating(
              episodeTitle: item.episode.title, podcastTitle: item.podcastTitle)
        }
      }
    }
  }

  // MARK: - Helpers

  private func label(for preset: Int) -> LocalizedStringResource {
    switch preset {
    case 0: "None — only future episodes"
    case items.count: order == .newest ? "All episodes" : "All in Up Next"
    default: order == .newest ? "Latest \(preset)" : "Next \(preset)"
    }
  }

  /// Episodes in the first `preset` that still need a transcript.
  private func toQueueCount(_ preset: Int) -> Int {
    needsTranscript.prefix(preset).count(where: \.self)
  }

  private func confirm() {
    guard selectedLimit > 0 else { return dismiss() }
    // .blocked only means "not charging"; the caution was already on screen,
    // so this one batch runs on battery. Auto transcribe still waits to charge.
    let engine: TranscriptEngine = switch TranscriptManager.shared.resolveAutoTranscribeEngine() {
    case .yap: .yapServer
    case .local(let local): local
    case .blocked: TranscriptManager.defaultEngine
    }
    TranscriptManager.shared.queueBatch(Array(items.prefix(selectedLimit)), engine: engine)
    dismiss()
  }
}

extension TranscribeBackfillSheet {
  /// A show's episodes, newest first.
  init(podcast: PodcastInfo, offersNone: Bool = false) {
    self.init(
      title: podcast.title,
      items: podcast.episodes
        .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
        .map { BatchTranscriptItem(episode: $0, podcastTitle: podcast.title, language: podcast.language) },
      offersNone: offersNone
    )
  }
}
