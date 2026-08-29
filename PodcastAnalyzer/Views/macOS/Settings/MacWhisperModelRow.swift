//
//  MacWhisperModelRow.swift
//  PodcastAnalyzer
//
//  One downloadable Whisper model row, macOS Preferences.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacWhisperModelRow: View {
  let variant: WhisperModelVariant
  private var manager: WhisperModelManager { .shared }

  var body: some View {
    let status = manager.status(for: variant)
    let isSelected = manager.selectedModel == variant

    Button(action: {
      if status.isReady { manager.setSelectedModel(variant) }
    }) {
      HStack(spacing: 10) {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? .blue : .secondary)

        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(variant.displayName)
              .fontWeight(isSelected ? .semibold : .regular)
            Text(variant.approximateSize)
              .font(.caption).foregroundStyle(.secondary)
            if variant == .platformDefault {
              Text("Recommended")
                .font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
            }
          }
          Text(variant.accuracyNote)
            .font(.caption2).foregroundStyle(.secondary)
        }

        Spacer()

        macWhisperAction(for: variant, status: status)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func macWhisperAction(
    for variant: WhisperModelVariant,
    status: WhisperModelStatus
  ) -> some View {
    switch status {
    case .notDownloaded:
      Button("Download") { manager.downloadModel(variant) }
        .buttonStyle(.accentProminent).controlSize(.small)
    case .downloading(let progress):
      HStack(spacing: 8) {
        ProgressView(value: progress).frame(width: 80)
        Text("\(Int(progress * 100))%").font(.caption).foregroundStyle(.secondary)
        Button("Cancel download", systemImage: "xmark.circle.fill") {
          manager.cancelDownload(variant)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
      }
    case .ready:
      HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        Button { manager.deleteModel(variant) } label: {
          Image(systemName: "trash").foregroundStyle(.red).font(.caption)
        }
        .buttonStyle(.plain)
        .help("Delete model from disk")
      }
    case .error(let message):
      HStack(spacing: 4) {
        Text("Error").foregroundStyle(.red).font(.caption)
        Button("Retry") { manager.downloadModel(variant) }
          .buttonStyle(.accentProminent).controlSize(.small)
      }
      .help(message)
    }
  }
}


#endif
