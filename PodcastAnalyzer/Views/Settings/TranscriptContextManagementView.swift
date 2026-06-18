//
//  TranscriptContextManagementView.swift
//  PodcastAnalyzer
//
//  Settings screen to manage each podcast's Transcription Context — a per-show
//  list of proper nouns / jargon (host & guest names, companies, terms) fed to
//  the SpeechAnalyzer as contextual strings so on-device transcription spells
//  them correctly. Stored on `PodcastInfoModel.transcriptionTerms` (survives
//  feed renames); separate from the AI "Show Format" hint.
//

import SwiftData
import SwiftUI

struct TranscriptContextManagementView: View {
  @Query(filter: #Predicate<PodcastInfoModel> { $0.isSubscribed }, sort: \.title)
  private var podcasts: [PodcastInfoModel]

  var body: some View {
    List {
      Section {
        ForEach(podcasts) { podcast in
          NavigationLink {
            TranscriptContextEditorView(podcast: podcast)
          } label: {
            let count = podcast.transcriptionTerms.count
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(podcast.title).lineLimit(1)
                Text(count > 0 ? "^[\(count) term](inflect: true)" : "No terms set")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              if count > 0 {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
              }
            }
          }
        }
      } header: {
        Text("Subscribed Podcasts")
      } footer: {
        Text("Add host and recurring guest names plus show-specific jargon. These terms bias on-device transcription so names come out spelled correctly.")
      }
    }
    .navigationTitle("Transcription Context")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .overlay {
      if podcasts.isEmpty {
        ContentUnavailableView(
          "No Subscriptions",
          systemImage: "character.book.closed",
          description: Text("Subscribe to a podcast to add transcription terms.")
        )
      }
    }
  }
}

// MARK: - Per-podcast term editor

/// Edits one show's transcription vocabulary as a list of terms (one per row),
/// persisting to `PodcastInfoModel.transcriptionTerms` on disappear. Reused both
/// pushed (from the management list) and presented as a sheet (transcript screen).
struct TranscriptContextEditorView: View {
  @Bindable var podcast: PodcastInfoModel
  @Environment(\.modelContext) private var modelContext

  private struct TermEntry: Identifiable { let id = UUID(); var text: String }
  @State private var entries: [TermEntry] = []

  var body: some View {
    List {
      Section {
        ForEach($entries) { $entry in
          TextField("Name or term", text: $entry.text)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.words)
            #endif
        }
        .onDelete { entries.remove(atOffsets: $0) }

        Button {
          entries.append(TermEntry(text: ""))
        } label: {
          Label("Add term", systemImage: "plus.circle.fill")
        }
      } header: {
        Text(podcast.title)
      } footer: {
        Text("One name or term per row — e.g. host and guest names, companies, or jargon the recognizer tends to get wrong. Leave empty to remove this show's context.")
      }
    }
    .navigationTitle("Edit Terms")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .onAppear(perform: load)
    .onDisappear(perform: save)
  }

  private func load() {
    entries = podcast.transcriptionTerms.map { TermEntry(text: $0) }
    if entries.isEmpty { entries = [TermEntry(text: "")] }  // one empty starter row
  }

  private func save() {
    let cleaned = entries
      .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard cleaned != podcast.transcriptionTerms else { return }
    podcast.transcriptionTerms = cleaned
    try? modelContext.save()
  }
}
