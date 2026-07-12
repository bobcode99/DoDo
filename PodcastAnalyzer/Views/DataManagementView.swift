//
//  DataManagementView.swift
//  PodcastAnalyzer
//
//  Separated view for managing app data: cache, downloads, transcripts, AI analysis
//

import SwiftData
import SwiftUI

struct DataManagementView: View {
  @Environment(\.modelContext) var modelContext

  // Data management state
  @State private var showClearCacheConfirmation = false
  @State private var showClearDownloadsConfirmation = false
  @State private var showClearTranscriptsConfirmation = false
  @State private var showClearAIAnalysisConfirmation = false
  @State private var isClearingData = false
  @State private var clearingMessage = ""

  // Storage info - loaded async
  @State private var imageCacheSize: String = "Calculating..."
  @State private var downloadedAudioSize: String = "Calculating..."
  @State private var transcriptsSize: String = "Calculating..."
  @State private var aiAnalysisCount: Int = 0
  @State private var isCalculating = true

  var body: some View {
    List {
      // MARK: - Storage Usage Section
      Section {
        // Clear Image Cache
        Button(action: {
          showClearCacheConfirmation = true
        }) {
          HStack {
            Image(systemName: "photo.on.rectangle")
              .foregroundStyle(.orange)
              .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text("Image Cache")
              if isCalculating {
                ProgressView()
                  .scaleEffect(0.6)
              } else {
                Text(imageCacheSize)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            Spacer()
            if isClearingData && clearingMessage == "cache" {
              ProgressView()
                .scaleEffect(0.8)
            } else {
              Text("Clear")
                .font(.subheadline)
                .foregroundStyle(.blue)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(isClearingData || isCalculating)

        // Clear All Downloads
        Button(action: {
          showClearDownloadsConfirmation = true
        }) {
          HStack {
            Image(systemName: "arrow.down.circle.fill")
              .foregroundStyle(.green)
              .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text("Downloaded Episodes")
              if isCalculating {
                ProgressView()
                  .scaleEffect(0.6)
              } else {
                Text(downloadedAudioSize)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            Spacer()
            if isClearingData && clearingMessage == "downloads" {
              ProgressView()
                .scaleEffect(0.8)
            } else {
              Text("Remove All")
                .font(.subheadline)
                .foregroundStyle(.red)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(isClearingData || isCalculating)

        // Clear All Transcripts
        Button(action: {
          showClearTranscriptsConfirmation = true
        }) {
          HStack {
            Image(systemName: "text.bubble")
              .foregroundStyle(.blue)
              .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text("Transcripts")
              if isCalculating {
                ProgressView()
                  .scaleEffect(0.6)
              } else {
                Text(transcriptsSize)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            Spacer()
            if isClearingData && clearingMessage == "transcripts" {
              ProgressView()
                .scaleEffect(0.8)
            } else {
              Text("Remove All")
                .font(.subheadline)
                .foregroundStyle(.red)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(isClearingData || isCalculating)

        // Clear All AI Analysis
        Button(action: {
          showClearAIAnalysisConfirmation = true
        }) {
          HStack {
            Image(systemName: "sparkles")
              .foregroundStyle(.purple)
              .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text("AI Analysis Data")
              if isCalculating {
                ProgressView()
                  .scaleEffect(0.6)
              } else {
                Text("\(aiAnalysisCount) analyses")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
            Spacer()
            if isClearingData && clearingMessage == "ai" {
              ProgressView()
                .scaleEffect(0.8)
            } else {
              Text("Remove All")
                .font(.subheadline)
                .foregroundStyle(.red)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(isClearingData || isCalculating)
      } header: {
        Text("Storage Usage")
      } footer: {
        Text("Clearing downloads and transcripts will free up storage space but won't affect your subscriptions")
      }

      // MARK: - Per-Podcast Transcripts
      Section {
        NavigationLink {
          PodcastTranscriptManagementView()
        } label: {
          HStack {
            Image(systemName: "text.bubble")
              .foregroundStyle(.blue)
              .frame(width: 24)
            Text("Manage Transcripts by Podcast")
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundStyle(.secondary)
              .font(.caption)
          }
        }
      } header: {
        Text("Per-Podcast Management")
      } footer: {
        Text("Delete transcripts for individual podcasts")
      }

      // MARK: - Storage Summary
      if !isCalculating {
        Section {
          HStack {
            Text("Total Storage Used")
            Spacer()
            Text(calculateTotalSize())
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle("Data Management")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .task {
      await calculateStorageInfoParallel()
    }
    // Confirmation dialogs
    .confirmationDialog(
      "Clear Image Cache",
      isPresented: $showClearCacheConfirmation,
      titleVisibility: .visible
    ) {
      Button("Clear Cache", role: .destructive) {
        clearImageCache()
      }
    } message: {
      Text("This will clear all cached podcast artwork. Images will be re-downloaded as needed.")
    }
    .confirmationDialog(
      "Remove All Downloads",
      isPresented: $showClearDownloadsConfirmation,
      titleVisibility: .visible
    ) {
      Button("Remove All Downloads", role: .destructive) {
        clearAllDownloads()
      }
    } message: {
      Text("This will delete all downloaded episodes. You can re-download them later.")
    }
    .confirmationDialog(
      "Remove All Transcripts",
      isPresented: $showClearTranscriptsConfirmation,
      titleVisibility: .visible
    ) {
      Button("Remove All Transcripts", role: .destructive) {
        clearAllTranscripts()
      }
    } message: {
      Text("This will delete all generated transcripts. You can regenerate them later.")
    }
    .confirmationDialog(
      "Remove All AI Analysis",
      isPresented: $showClearAIAnalysisConfirmation,
      titleVisibility: .visible
    ) {
      Button("Remove All Analysis", role: .destructive) {
        clearAllAIAnalysis()
      }
    } message: {
      Text("This will delete all AI-generated analysis data. You can regenerate them later.")
    }
  }

  // MARK: - Calculate Storage (Parallel)

  private func calculateStorageInfoParallel() async {
    isCalculating = true

    // Run all calculations in parallel
    async let cacheTask = calculateImageCacheSize()
    async let audioTask = calculateDownloadedAudioSize()
    async let captionsTask = calculateTranscriptsSize()
    async let analysisTask = countAIAnalyses()

    let (cacheSize, audioSize, captionsSize, analysisCount) = await (
      cacheTask, audioTask, captionsTask, analysisTask
    )

    imageCacheSize = formatBytes(cacheSize)
    downloadedAudioSize = formatBytes(audioSize)
    transcriptsSize = formatBytes(captionsSize)
    aiAnalysisCount = analysisCount
    isCalculating = false
  }

  private func calculateTotalSize() -> String {
    // Parse sizes back to calculate total (rough estimate)
    var total: Int64 = 0
    if let bytes = parseBytes(imageCacheSize) { total += bytes }
    if let bytes = parseBytes(downloadedAudioSize) { total += bytes }
    if let bytes = parseBytes(transcriptsSize) { total += bytes }
    return formatBytes(total)
  }

  private func parseBytes(_ str: String) -> Int64? {
    let parts = str.components(separatedBy: " ")
    guard parts.count == 2, let value = Double(parts[0]) else { return nil }
    let unit = parts[1]
    switch unit {
    case "KB": return Int64(value * 1024)
    case "MB": return Int64(value * 1024 * 1024)
    case "GB": return Int64(value * 1024 * 1024 * 1024)
    default: return Int64(value)
    }
  }

  private func calculateImageCacheSize() async -> Int64 {
    ImageCacheUtility.dataCacheTotalSize()
  }

  private func calculateDownloadedAudioSize() async -> Int64 {
    await Task.detached(priority: .utility) {
      let fileManager = FileManager.default
      let libraryDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      let audioDir = libraryDir.appendingPathComponent("Audio")

      guard let enumerator = fileManager.enumerator(
        at: audioDir,
        includingPropertiesForKeys: [.fileSizeKey]
      ) else { return Int64(0) }

      var totalSize: Int64 = 0
      while let fileURL = enumerator.nextObject() as? URL {
        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
          totalSize += Int64(size)
        }
      }
      return totalSize
    }.value
  }

  private func calculateTranscriptsSize() async -> Int64 {
    await Task.detached(priority: .utility) {
      let fileManager = FileManager.default
      let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
      let captionsDir = documentsDir.appendingPathComponent("Captions")

      guard let enumerator = fileManager.enumerator(
        at: captionsDir,
        includingPropertiesForKeys: [.fileSizeKey]
      ) else { return Int64(0) }

      var totalSize: Int64 = 0
      while let fileURL = enumerator.nextObject() as? URL {
        if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
          totalSize += Int64(size)
        }
      }
      return totalSize
    }.value
  }

  private func countAIAnalyses() async -> Int {
    let descriptor = FetchDescriptor<EpisodeAIAnalysis>()
    return (try? modelContext.fetchCount(descriptor)) ?? 0
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  // MARK: - Clear Actions

  private func clearImageCache() {
    isClearingData = true
    clearingMessage = "cache"

    ImageCacheUtility.clearAllCache()
    imageCacheSize = "0 KB"
    isClearingData = false
    clearingMessage = ""
  }

  private func clearAllDownloads() {
    isClearingData = true
    clearingMessage = "downloads"

    Task {
      // Clear files
      await Task.detached(priority: .utility) {
        let fileManager = FileManager.default
        let libraryDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let audioDir = libraryDir.appendingPathComponent("Audio")
        try? fileManager.removeItem(at: audioDir)
        try? fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)
      }.value

      // Clear SwiftData records
      let descriptor = FetchDescriptor<EpisodeDownloadModel>()
      if let episodes = try? modelContext.fetch(descriptor) {
        for episode in episodes {
          if episode.localAudioPath != nil {
            episode.localAudioPath = nil
            episode.downloadedDate = nil
            episode.fileSize = 0
          }
        }
        try? modelContext.save()
      }
      downloadedAudioSize = "0 KB"
      isClearingData = false
      clearingMessage = ""
    }
  }

  private func clearAllTranscripts() {
    isClearingData = true
    clearingMessage = "transcripts"

    Task {
      // Clear files
      await Task.detached(priority: .utility) {
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let captionsDir = documentsDir.appendingPathComponent("Captions")
        try? fileManager.removeItem(at: captionsDir)
        try? fileManager.createDirectory(at: captionsDir, withIntermediateDirectories: true)
      }.value

      // Clear SwiftData records
      let descriptor = FetchDescriptor<EpisodeDownloadModel>()
      if let episodes = try? modelContext.fetch(descriptor) {
        for episode in episodes {
          if episode.captionPath != nil {
            episode.captionPath = nil
          }
        }
        try? modelContext.save()
      }
      transcriptsSize = "0 KB"
      isClearingData = false
      clearingMessage = ""
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
        try? modelContext.save()
      }
      aiAnalysisCount = 0
      isClearingData = false
      clearingMessage = ""
    }
  }
}
