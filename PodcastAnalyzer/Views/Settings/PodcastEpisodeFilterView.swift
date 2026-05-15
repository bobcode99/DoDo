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
            try? modelContext.save()
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
