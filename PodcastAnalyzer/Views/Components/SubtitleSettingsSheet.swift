//
//  SubtitleSettingsSheet.swift
//  PodcastAnalyzer
//
//  Settings sheet for subtitle display and translation options
//

import SwiftUI

struct SubtitleSettingsSheet: View {
  @Environment(\.dismiss) private var dismiss
  private var settings: SubtitleSettingsManager { .shared }

  /// Whether translation exists for the current episode
  var hasTranslation: Bool = false

  /// Effective mode clamps to .originalOnly when translation is unavailable,
  /// so a saved dual-subtitle preference doesn't look "selected" on untranslated episodes.
  private var effectiveMode: SubtitleDisplayMode {
    let stored = settings.displayMode
    guard stored.requiresTranslation else { return stored }
    return hasTranslation ? stored : .originalOnly
  }

  var body: some View {
    NavigationStack {
      Form {
        // Display Mode Section
        Section {
          ForEach(SubtitleDisplayMode.allCases, id: \.self) { mode in
            Button {
              settings.displayMode = mode
            } label: {
              HStack {
                Label(mode.displayName, systemImage: mode.icon)
                  .foregroundStyle(mode.requiresTranslation && !hasTranslation ? .tertiary : .primary)
                Spacer()
                if effectiveMode == mode {
                  Image(systemName: "checkmark")
                    .foregroundStyle(.blue)
                }
              }
            }
            .disabled(mode.requiresTranslation && !hasTranslation)
          }
        } header: {
          Text("Display Mode")
        } footer: {
          if hasTranslation {
            Text(effectiveMode.description)
          } else {
            Text("Translate the transcript to unlock additional display modes")
          }
        }

        // Info Section
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text("Transcript Sources")
              .font(.subheadline.bold())
            Text("Transcripts can come from:")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("- RSS feed (podcast:transcript tag)")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text("- On-device speech recognition")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 4)
        } header: {
          Text("About")
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Subtitle Settings")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}

#Preview {
  SubtitleSettingsSheet()
}
