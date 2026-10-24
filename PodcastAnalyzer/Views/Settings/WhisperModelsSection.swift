//
//  WhisperModelsSection.swift
//  PodcastAnalyzer
//
//  Whisper model management section for Settings.
//

import SwiftUI

// MARK: - Whisper Models Section

/// Settings section for downloading / managing WhisperKit models.
/// Shown inline inside the List when the user selects the Whisper engine.
struct WhisperModelsSection: View {
  var body: some View {
    Section {
      ForEach(WhisperModelVariant.allCases.filter { $0.isSuitableForCurrentPlatform }) { variant in
        WhisperModelRow(variant: variant)
      }
    } header: {
      Text("Whisper Models")
    } footer: {
      Text("Download a model to enable Whisper transcription. \(WhisperModelVariant.platformDefault.displayName) is recommended for this device.")
    }
  }
}

struct WhisperModelRow: View {
  let variant: WhisperModelVariant
  private var manager: WhisperModelManager { .shared }

  var body: some View {
    let status = manager.status(for: variant)
    let isSelected = manager.selectedModel == variant

    // The row's select button and its download / cancel / delete button are
    // siblings: a Button nested inside another Button's label is folded into
    // it for VoiceOver, so the inner action could not be focused.
    HStack(spacing: 12) {
      Button {
        if status.isReady {
          manager.setSelectedModel(variant)
        }
      } label: {
        HStack(spacing: 12) {
          // Selected indicator
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(isSelected ? .blue : .secondary)
            .frame(width: 20)
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              Text(variant.displayName)
                .fontWeight(isSelected ? .semibold : .regular)
              Text(variant.approximateSize)
                .font(.caption)
                .foregroundStyle(.secondary)
              if variant == .platformDefault {
                Text("Recommended")
                  .font(.caption2)
                  .padding(.horizontal, 5)
                  .padding(.vertical, 2)
                  .background(Color.blue.opacity(0.15))
                  .foregroundStyle(.blue)
                  .clipShape(.capsule)
              }
            }
            Text(variant.accuracyNote)
              .font(.caption2)
              .foregroundStyle(.secondary)
            if case .error(let message) = status {
              Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
            }
          }

          Spacer()
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityAddTraits(isSelected ? .isSelected : [])

      // Status / action
      whisperModelAction(for: variant, status: status)
    }
    .padding(.vertical, 2)
  }

  @ViewBuilder
  private func whisperModelAction(
    for variant: WhisperModelVariant,
    status: WhisperModelStatus
  ) -> some View {
    switch status {
    case .notDownloaded:
      Button("Download") {
        manager.downloadModel(variant)
      }
      .buttonStyle(.accentProminent)
      .controlSize(.small)

    case .downloading(let progress):
      HStack(spacing: 8) {
        VStack(alignment: .trailing, spacing: 2) {
          ProgressView(value: progress)
            .frame(width: 60)
          Text("\(Int(progress * 100))%")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Button {
          manager.cancelDownload(variant)
        } label: {
          Label("Cancel download", systemImage: "xmark.circle.fill")
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
      }

    case .ready:
      HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .accessibilityHidden(true)
        Button {
          manager.deleteModel(variant)
        } label: {
          Label("Delete \(variant.displayName)", systemImage: "trash")
            .labelStyle(.iconOnly)
            .foregroundStyle(.red)
            .font(.caption)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
      }

    case .error(let message):
      VStack(alignment: .trailing, spacing: 2) {
        Text("Failed")
          .font(.caption)
          .foregroundStyle(.red)
        Button("Retry") {
          manager.downloadModel(variant)
        }
        .buttonStyle(.accentProminent)
        .controlSize(.mini)
      }
      .help(message)
    }
  }
}
