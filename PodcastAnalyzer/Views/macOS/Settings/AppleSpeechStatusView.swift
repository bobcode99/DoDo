//
//  AppleSpeechStatusView.swift
//  PodcastAnalyzer
//
//  Apple Speech model availability row, macOS Preferences.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct AppleSpeechStatusView: View {
  let viewModel: SettingsViewModel

  var body: some View {
    switch viewModel.transcriptModelStatus {
    case .checking:
      HStack(spacing: 8) {
        ProgressView().scaleEffect(0.7)
        Text("Checking...").foregroundStyle(.secondary)
      }
    case .notDownloaded:
      HStack(spacing: 8) {
        Text("Not installed").foregroundStyle(.orange)
        Button("Download") { viewModel.downloadTranscriptModel() }
          .buttonStyle(.accentProminent).controlSize(.small)
      }
    case .downloading(let progress):
      HStack(spacing: 8) {
        ProgressView(value: progress).frame(width: 80)
        Text("\(Int(progress * 100))%").foregroundStyle(.secondary)
        Button("Cancel download", systemImage: "xmark.circle.fill") {
          viewModel.cancelTranscriptDownload()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
      }
    case .ready:
      HStack(spacing: 4) {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        Text("Ready").foregroundStyle(.green)
      }
    case .error(let message):
      HStack(spacing: 8) {
        Text(message).foregroundStyle(.red).lineLimit(1)
        Button("Retry") { viewModel.downloadTranscriptModel() }
          .buttonStyle(.accentProminent).controlSize(.small)
      }
    case .simulatorNotSupported:
      Text("Requires physical device").foregroundStyle(.secondary)
    }
  }
}


#endif
