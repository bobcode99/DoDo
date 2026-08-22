//
//  PodcastEpisodeFilterView.swift
//  PodcastAnalyzer
//
//  Sheet that lets users configure per-podcast episode auto-download filters.
//

import SwiftData
import SwiftUI

struct PodcastEpisodeFilterView: View {
  let podcast: PodcastInfoModel
  let modelContext: ModelContext
  /// Optional callback fired after the user taps Done and the filter values
  /// have been persisted. `EpisodeListView` uses it to auto-select the
  /// `.custom` chip so the configured filter is immediately visible — without
  /// this, the list reverts to whichever chip was selected before the sheet
  /// opened (almost always `.all`) and the configured terms appear to do
  /// nothing.
  var onSave: (() -> Void)? = nil
  @Environment(\.dismiss) private var dismiss

  @State private var includeTerms: String = ""
  @State private var excludeTerms: String = ""
  @State private var minDurationMinutes: Int = 0

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("e.g. AI, interview", text: $includeTerms)
            .autocorrectionDisabled()
        } header: {
          Text("Include terms")
        } footer: {
          Text("Auto-download only episodes whose title contains at least one of these terms. Separate terms with commas.")
        }

        Section {
          TextField("e.g. ads, premium", text: $excludeTerms)
            .autocorrectionDisabled()
        } header: {
          Text("Exclude terms")
        } footer: {
          Text("Skip episodes whose title contains any of these terms. Exclude wins over include.")
        }

        Section {
          Stepper("Minimum \(minDurationMinutes) min", value: $minDurationMinutes, in: 0...600, step: 5)
        } header: {
          Text("Minimum duration")
        } footer: {
          Text("Skip episodes shorter than this duration. 0 = no minimum.")
        }
      }
      .navigationTitle("Episode Filter")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            podcast.episodeFilterInclude = includeTerms.trimmingCharacters(in: .whitespaces)
            podcast.episodeFilterExclude = excludeTerms.trimmingCharacters(in: .whitespaces)
            podcast.episodeFilterMinDuration = minDurationMinutes * 60
            modelContext.saveOrLog()
            onSave?()
            dismiss()
          }
        }
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
      .onAppear {
        includeTerms = podcast.episodeFilterInclude
        excludeTerms = podcast.episodeFilterExclude
        minDurationMinutes = podcast.episodeFilterMinDuration / 60
      }
    }
  }
}
