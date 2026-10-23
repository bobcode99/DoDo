//
//  StorageSettingsTab.swift
//  PodcastAnalyzer
//
//  Storage pane of the macOS Preferences window.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct StorageSettingsTab: View {
  @Environment(\.modelContext) private var modelContext

  @State private var imageCacheSize: Int64?
  @State private var downloadedAudioSize: Int64?
  @State private var transcriptsSize: Int64?
  @State private var aiAnalysisCount: Int = 0

  @State private var isClearingData = false
  @State private var clearingMessage = ""

  @State private var showClearCacheAlert = false
  @State private var showClearDownloadsAlert = false
  @State private var showClearTranscriptsAlert = false
  @State private var showClearAIAlert = false

  var body: some View {
    Form {
      Section {
        storageRow(
          icon: "photo.on.rectangle",
          iconColor: .orange,
          title: "Image Cache",
          size: sizeText(imageCacheSize),
          isClearing: isClearingData && clearingMessage == "cache"
        ) {
          showClearCacheAlert = true
        }

        storageRow(
          icon: "arrow.down.circle.fill",
          iconColor: .green,
          title: "Downloaded Episodes",
          size: sizeText(downloadedAudioSize),
          isClearing: isClearingData && clearingMessage == "downloads",
          isDestructive: true
        ) {
          showClearDownloadsAlert = true
        }

        storageRow(
          icon: "text.bubble",
          iconColor: .blue,
          title: "Transcripts",
          size: sizeText(transcriptsSize),
          isClearing: isClearingData && clearingMessage == "transcripts",
          isDestructive: true
        ) {
          showClearTranscriptsAlert = true
        }

        storageRow(
          icon: "sparkles",
          iconColor: .purple,
          title: "AI Analysis Data",
          size: Text("\(aiAnalysisCount) analyses"),
          isClearing: isClearingData && clearingMessage == "ai",
          isDestructive: true
        ) {
          showClearAIAlert = true
        }
      } header: {
        Text("Data Management")
      } footer: {
        Text("Clearing downloads and transcripts will free up storage space but won't affect your subscriptions.")
      }
    }
    .formStyle(.grouped)
    .padding()
    .task {
      await calculateStorageInfo()
    }
    .alert("Clear Image Cache", isPresented: $showClearCacheAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Clear", role: .destructive) { clearImageCache() }
    } message: {
      Text("This will remove all cached images. They will be re-downloaded when needed.")
    }
    .alert("Remove All Downloads", isPresented: $showClearDownloadsAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Remove All", role: .destructive) { clearAllDownloads() }
    } message: {
      Text("This will delete all downloaded episodes. You can re-download them later.")
    }
    .alert("Remove All Transcripts", isPresented: $showClearTranscriptsAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Remove All", role: .destructive) { clearAllTranscripts() }
    } message: {
      Text("This will delete all generated transcripts. You can regenerate them later.")
    }
    .alert("Remove All AI Analysis", isPresented: $showClearAIAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Remove All", role: .destructive) { clearAllAIAnalysis() }
    } message: {
      Text("This will delete all AI-generated summaries, entities, highlights, and Q&A history.")
    }
  }

  @ViewBuilder
  private func storageRow(
    icon: String,
    iconColor: Color,
    title: LocalizedStringResource,
    size: Text,
    isClearing: Bool,
    isDestructive: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      Image(systemName: icon)
        .foregroundStyle(iconColor)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
        size
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if isClearing {
        ProgressView()
          .controlSize(.small)
      } else {
        Button(isDestructive ? "Remove All" : "Clear") {
          action()
        }
        .foregroundStyle(isDestructive ? .red : .blue)
      }
    }
    .buttonStyle(.plain)
  }

  // MARK: - Storage Calculations

  private func calculateStorageInfo() async {
    imageCacheSize = await calculateImageCacheSize()
    downloadedAudioSize = await calculateDownloadedAudioSize()
    transcriptsSize = await calculateTranscriptsSize()

    let analysisCount = countAIAnalyses()
    aiAnalysisCount = analysisCount
  }

  private func calculateImageCacheSize() async -> Int64 {
    ImageCacheUtility.dataCacheTotalSize()
  }

  private func calculateDownloadedAudioSize() async -> Int64 {
    await FileStorageManager.shared.calculateTotalAudioSize()
  }

  private func calculateTranscriptsSize() async -> Int64 {
    TranscriptStore.shared.totalStorageSize()
  }

  private func countAIAnalyses() -> Int {
    let descriptor = FetchDescriptor<EpisodeAIAnalysis>()
    return (try? modelContext.fetchCount(descriptor)) ?? 0
  }

  private func sizeText(_ bytes: Int64?) -> Text {
    if let bytes {
      Text(bytes, format: .byteCount(style: .file))
    } else {
      Text("Calculating...")
    }
  }

  // MARK: - Clear Actions

  private func clearImageCache() {
    isClearingData = true
    clearingMessage = "cache"

    Task {
      ImageCacheUtility.clearAllCache()
      isClearingData = false
      clearingMessage = ""
      imageCacheSize = 0
    }
  }

  private func clearAllDownloads() {
    isClearingData = true
    clearingMessage = "downloads"

    Task {
      let descriptor = FetchDescriptor<EpisodeDownloadModel>(
        predicate: #Predicate { $0.localAudioPath != nil }
      )

      if let downloadedEpisodes = try? modelContext.fetch(descriptor) {
        for episode in downloadedEpisodes {
          if let localPath = episode.localAudioPath {
            try? FileManager.default.removeItem(atPath: localPath)
          }
          episode.localAudioPath = nil
          episode.downloadedDate = nil
          episode.fileSize = 0
        }
        modelContext.saveOrLog()
      }

      await FileStorageManager.shared.clearAllAudioFiles()

      isClearingData = false
      clearingMessage = ""
      downloadedAudioSize = 0
    }
  }

  private func clearAllTranscripts() {
    isClearingData = true
    clearingMessage = "transcripts"

    Task {
      try? TranscriptStore.shared.deleteAll()

      isClearingData = false
      clearingMessage = ""
      transcriptsSize = 0
    }
  }

  private func clearAllAIAnalysis() {
    isClearingData = true
    clearingMessage = "ai"

    Task {
      let descriptor = FetchDescriptor<EpisodeAIAnalysis>()
      if let analyses = try? modelContext.fetch(descriptor) {
        for analysis in analyses {
          modelContext.delete(analysis)
        }
        modelContext.saveOrLog()
      }

      isClearingData = false
      clearingMessage = ""
      aiAnalysisCount = 0
    }
  }
}

#endif
