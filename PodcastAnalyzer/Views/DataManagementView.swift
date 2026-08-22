//
//  DataManagementView.swift
//  PodcastAnalyzer
//
//  Separated view for managing app data: cache, downloads, transcripts, AI analysis
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DataManagementView: View {
  @Environment(\.modelContext) var modelContext

  // Data management state
  @State private var showClearCacheConfirmation = false
  @State private var showClearDownloadsConfirmation = false
  @State private var showClearTranscriptsConfirmation = false
  @State private var showClearAIAnalysisConfirmation = false
  @State private var isClearingData = false
  @State private var clearingMessage = ""
  @State private var opmlExportItem: ShareableOPML?
  @State private var diagnosticExportItem: ShareableOPML?
  @State private var backupExportItem: ShareableOPML?
  @State private var showBackupImporter = false
  @State private var backupErrorAlert: String?
  @Bindable private var backupService = BackupService.shared

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

      // MARK: - Export Section
      Section {
        Button(action: exportOPML) {
          HStack {
            Image(systemName: "square.and.arrow.up")
              .foregroundStyle(.blue)
              .frame(width: 24)
            Text("Export Subscriptions (OPML)")
          }
        }
        .buttonStyle(.plain)

        Button(action: exportDiagnosticReport) {
          HStack {
            Image(systemName: "doc.text.magnifyingglass")
              .foregroundStyle(.purple)
              .frame(width: 24)
            Text("Export Diagnostic Report")
          }
        }
        .buttonStyle(.plain)
      } header: {
        Text("Export")
      } footer: {
        Text("OPML exports your subscriptions for use in other apps. Diagnostic report bundles logs and settings for support.")
      }

      // MARK: - Backup & Restore
      Section {
        Button(action: exportFullBackup) {
          HStack {
            Image(systemName: "tray.and.arrow.up.fill")
              .foregroundStyle(.indigo)
              .frame(width: 24)
            Text("Export Full Backup")
            Spacer()
            if BackupService.shared.isExporting {
              ProgressView().scaleEffect(0.7)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(BackupService.shared.isExporting || BackupService.shared.isImporting)

        Button {
          showBackupImporter = true
        } label: {
          HStack {
            Image(systemName: "tray.and.arrow.down.fill")
              .foregroundStyle(.indigo)
              .frame(width: 24)
            Text("Restore from Backup")
            Spacer()
            if BackupService.shared.isImporting {
              ProgressView().scaleEffect(0.7)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(
          BackupService.shared.isExporting
            || BackupService.shared.isImporting
            || PodcastImportManager.shared.isImporting
        )
      } header: {
        Text("Backup & Restore")
      } footer: {
        Text("Backs up subscriptions, full playback history, queue, AI analyses, and settings as a single JSON file. Restore on a new device with smart merge — your existing data is never deleted. Local audio, captions, and credentials are not included.")
      }
    }
    .sheet(item: $opmlExportItem) { item in
      ShareSheet(items: [item.url])
    }
    .sheet(item: $diagnosticExportItem) { item in
      ShareSheet(items: [item.url])
    }
    .sheet(item: $backupExportItem) { item in
      ShareSheet(items: [item.url])
    }
    .sheet(isPresented: $backupService.showProgressSheet) {
      BackupProgressSheet()
    }
    .fileImporter(
      isPresented: $showBackupImporter,
      allowedContentTypes: [.json],
      allowsMultipleSelection: false
    ) { result in
      handleBackupImport(result)
    }
    .alert("Backup Error", isPresented: Binding(
      get: { backupErrorAlert != nil },
      set: { if !$0 { backupErrorAlert = nil } }
    )) {
      Button("OK", role: .cancel) { backupErrorAlert = nil }
    } message: {
      Text(backupErrorAlert ?? "")
    }
    .navigationTitle("Data Management")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .task {
      BackupService.shared.setModelContext(modelContext)
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
    TranscriptStore.shared.totalStorageSize()
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
        modelContext.saveOrLog()
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
      try? TranscriptStore.shared.deleteAll()
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
        modelContext.saveOrLog()
      }
      aiAnalysisCount = 0
      isClearingData = false
      clearingMessage = ""
    }
  }

  // MARK: - Diagnostic Export

  private func exportDiagnosticReport() {
    Task {
      // Gather library stats
      let podcastDescriptor = FetchDescriptor<PodcastInfoModel>(
        predicate: #Predicate { $0.isSubscribed == true }
      )
      let podcastCount = (try? modelContext.fetch(podcastDescriptor).count) ?? 0

      let episodeDescriptor = FetchDescriptor<EpisodeDownloadModel>()
      let episodeCount = (try? modelContext.fetch(episodeDescriptor).count) ?? 0

      // Build report
      var report: [String: Any] = [:]
      report["appVersion"] = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown"
      report["build"] = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unknown"
      report["osVersion"] = ProcessInfo.processInfo.operatingSystemVersionString
      report["date"] = ISO8601DateFormatter().string(from: Date())
      report["subscribedPodcasts"] = podcastCount
      report["trackedEpisodes"] = episodeCount

      // Include non-sensitive UserDefaults keys (skip API keys)
      let safeKeys = [
        "transcriptEngine", "selectedTranscriptLocale", "defaultPlaybackSpeed",
        "autoPlayNextEpisode", "autoDownloadNewEpisodes", "showTrendingEpisodes",
        "skipForwardInterval", "skipBackwardInterval", "selectedPodcastRegion"
      ]
      var settingsSnapshot: [String: Any] = [:]
      for key in safeKeys {
        settingsSnapshot[key] = UserDefaults.standard.object(forKey: key) ?? "not set"
      }
      report["settings"] = settingsSnapshot

      // Serialize
      guard let jsonData = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted),
            let jsonString = String(data: jsonData, encoding: .utf8) else { return }

      // Append recent log file if available
      let logURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("app_logs.txt")
      var fullReport = "=== Diagnostic Report ===\n\n" + jsonString
      if let logURL, let logs = try? String(contentsOf: logURL, encoding: .utf8) {
        fullReport += "\n\n=== Recent Logs ===\n" + logs.suffix(8000)
      }

      let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("diagnostic_report.txt")
      try? fullReport.write(to: tempURL, atomically: true, encoding: .utf8)
      diagnosticExportItem = ShareableOPML(url: tempURL)
    }
  }

  // MARK: - Full Backup Export / Import

  private func exportFullBackup() {
    Task {
      do {
        let url = try await BackupService.shared.exportBackup()
        backupExportItem = ShareableOPML(url: url)
      } catch {
        backupErrorAlert = error.localizedDescription
      }
    }
  }

  private func handleBackupImport(_ result: Result<[URL], Error>) {
    switch result {
    case .failure(let error):
      // User cancellation surfaces as a CocoaError with code .userCancelled.
      let nsError = error as NSError
      if nsError.code != NSUserCancelledError {
        backupErrorAlert = error.localizedDescription
      }
    case .success(let urls):
      guard let fileURL = urls.first else { return }
      Task {
        await BackupService.shared.importBackup(from: fileURL)
        if let err = BackupService.shared.lastError {
          backupErrorAlert = err
          BackupService.shared.showProgressSheet = false
        }
      }
    }
  }

  // MARK: - OPML Export

  private func exportOPML() {
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.isSubscribed == true }
    )
    guard let models = try? modelContext.fetch(descriptor) else { return }
    let podcasts = models.map { $0.podcastInfo }
    let opmlString = OPMLParser.export(podcasts: podcasts)

    // Write to a temp file so ShareSheet/ShareLink can share it
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("subscriptions.opml")
    try? opmlString.write(to: tempURL, atomically: true, encoding: .utf8)
    opmlExportItem = ShareableOPML(url: tempURL)
  }
}

// MARK: - Helpers

struct ShareableOPML: Identifiable {
  let id = UUID()
  let url: URL
}

// MARK: - Backup Progress Sheet

struct BackupProgressSheet: View {
  @Bindable private var service = BackupService.shared
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Group {
        if service.isImporting {
          progressContent
        } else if let summary = service.lastSummary {
          summaryContent(summary)
        } else {
          progressContent
        }
      }
      .navigationTitle("Restore Backup")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            service.dismissProgressSheet()
            dismiss()
          }
          .disabled(service.isImporting)
        }
      }
    }
    .interactiveDismissDisabled(service.isImporting)
  }

  private var progressContent: some View {
    VStack(spacing: 24) {
      ProgressView(value: service.progress)
        .progressViewStyle(.linear)
      Text(service.status)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }

  private func summaryContent(_ s: BackupService.ImportSummary) -> some View {
    List {
      Section("Podcasts") {
        statRow("Subscribed", value: "\(s.podcastsAdded) added · \(s.podcastsMerged) already in library")
        if s.podcastsFailed > 0 {
          statRow("Failed", value: "\(s.podcastsFailed)").foregroundStyle(.red)
        }
      }
      Section("Episode History") {
        statRow("New episodes", value: "\(s.episodesInserted)")
        statRow("Merged", value: "\(s.episodesUpdated)")
      }
      Section("Other") {
        statRow("Queue items", value: "\(s.queueReplaced)")
        statRow("AI analyses", value: "\(s.analysesUpserted)")
        statRow("Quick tags", value: "\(s.quickTagsUpserted)")
        statRow("Settings", value: "\(s.settingsApplied)")
      }
      if !s.warnings.isEmpty {
        Section("Warnings") {
          ForEach(s.warnings.indices, id: \.self) { idx in
            Text(s.warnings[idx])
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func statRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label)
      Spacer()
      Text(value).foregroundStyle(.secondary)
    }
  }
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
  let items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }
  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct ShareSheet: View {
  let items: [Any]
  var body: some View {
    if let url = items.first as? URL {
      ShareLink(item: url) {
        Label("Share OPML", systemImage: "square.and.arrow.up")
      }
      .padding()
    }
  }
}
#endif
