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
  @Environment(\.modelContext) private var modelContext

  private enum StorageCategory {
    case imageCache, downloads, transcripts, aiAnalysis
  }

  // Data management state
  @State private var clearing: StorageCategory?
  @State private var shareItem: ShareableOPML?
  @State private var showBackupImporter = false
  @State private var backupErrorAlert: String?
  @State private var actionError: String?
  @Bindable private var backupService = BackupService.shared

  // Storage info - loaded async
  @State private var imageCacheBytes: Int64 = 0
  @State private var downloadedAudioBytes: Int64 = 0
  @State private var transcriptsBytes: Int64 = 0
  @State private var aiAnalysisCount: Int = 0
  @State private var isCalculating = true

  private var totalBytes: Int64 {
    imageCacheBytes + downloadedAudioBytes + transcriptsBytes
  }

  private func sizeText(_ bytes: Int64) -> Text? {
    isCalculating ? nil : Text(bytes, format: Self.byteStyle)
  }

  private static let byteStyle = ByteCountFormatStyle(
    style: .file, allowedUnits: [.kb, .mb, .gb], spellsOutZero: false)

  var body: some View {
    List {
      // MARK: - Storage Usage Section
      Section {
        StorageUsageRow(
          systemImage: "photo.on.rectangle",
          tint: .orange,
          title: "Image Cache",
          detail: sizeText(imageCacheBytes),
          actionTitle: "Clear",
          actionTint: .blue,
          isBusy: clearing == .imageCache,
          isDisabled: clearing != nil || isCalculating,
          confirmationTitle: "Clear Image Cache",
          confirmationMessage: "This will clear all cached podcast artwork. Images will be re-downloaded as needed.",
          confirmButtonTitle: "Clear Cache"
        ) { clear(.imageCache) }

        StorageUsageRow(
          systemImage: "arrow.down.circle.fill",
          tint: .green,
          title: "Downloaded Episodes",
          detail: sizeText(downloadedAudioBytes),
          actionTitle: "Remove All",
          actionTint: .red,
          isBusy: clearing == .downloads,
          isDisabled: clearing != nil || isCalculating,
          confirmationTitle: "Remove All Downloads",
          confirmationMessage: "This will delete all downloaded episodes. You can re-download them later.",
          confirmButtonTitle: "Remove All Downloads"
        ) { clear(.downloads) }

        StorageUsageRow(
          systemImage: "text.bubble",
          tint: .blue,
          title: "Transcripts",
          detail: sizeText(transcriptsBytes),
          actionTitle: "Remove All",
          actionTint: .red,
          isBusy: clearing == .transcripts,
          isDisabled: clearing != nil || isCalculating,
          confirmationTitle: "Remove All Transcripts",
          confirmationMessage: "This will delete all generated transcripts. You can regenerate them later.",
          confirmButtonTitle: "Remove All Transcripts"
        ) { clear(.transcripts) }

        StorageUsageRow(
          systemImage: "sparkles",
          tint: .purple,
          title: "AI Analysis Data",
          detail: isCalculating ? nil : Text("\(aiAnalysisCount) analyses"),
          actionTitle: "Remove All",
          actionTint: .red,
          isBusy: clearing == .aiAnalysis,
          isDisabled: clearing != nil || isCalculating,
          confirmationTitle: "Remove All AI Analysis",
          confirmationMessage: "This will delete all AI-generated analysis data. You can regenerate them later.",
          confirmButtonTitle: "Remove All Analysis"
        ) { clear(.aiAnalysis) }
      } header: {
        Text("Storage Usage")
      } footer: {
        Text("Clearing downloads and transcripts will free up storage space but won't affect your subscriptions")
      }

      // MARK: - Storage Summary
      if !isCalculating {
        Section {
          LabeledContent("Total Storage Used") {
            Text(totalBytes, format: Self.byteStyle)
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
              .accessibilityHidden(true)
            Text("Export Subscriptions (OPML)")
          }
        }
        .buttonStyle(.plain)

        Button(action: exportDiagnosticReport) {
          HStack {
            Image(systemName: "doc.text.magnifyingglass")
              .foregroundStyle(.purple)
              .frame(width: 24)
              .accessibilityHidden(true)
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
              .accessibilityHidden(true)
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
              .accessibilityHidden(true)
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
    .sheet(item: $shareItem) { item in
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
    .alert("Backup Error", item: $backupErrorAlert) { _ in
      Button("OK", role: .cancel) {}
    } message: { error in
      Text(error)
    }
    .alert("Error", item: $actionError) { _ in
      Button("OK", role: .cancel) {}
    } message: { error in
      Text(error)
    }
    .navigationTitle("Data Management")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
    .task {
      BackupService.shared.setModelContext(modelContext)
      await calculateStorageInfo()
    }
  }

  // MARK: - Calculate Storage

  private func calculateStorageInfo() async {
    isCalculating = true

    // The audio walk runs on the FileStorageManager actor; the rest is cheap.
    async let audioBytes = FileStorageManager.shared.getTotalAudioSize()
    imageCacheBytes = ImageCacheUtility.dataCacheTotalSize()
    transcriptsBytes = TranscriptStore.shared.totalStorageSize()
    aiAnalysisCount = (try? modelContext.fetchCount(FetchDescriptor<EpisodeAIAnalysis>())) ?? 0
    downloadedAudioBytes = await audioBytes
    isCalculating = false
  }

  // MARK: - Clear Actions

  private func clear(_ category: StorageCategory) {
    clearing = category
    Task {
      defer { clearing = nil }
      do {
        switch category {
        case .imageCache:
          ImageCacheUtility.clearAllCache()
          imageCacheBytes = 0
        case .downloads:
          try await Self.removeDownloadedAudio()
          for episode in try modelContext.fetch(FetchDescriptor<EpisodeDownloadModel>())
          where episode.localAudioPath != nil {
            episode.localAudioPath = nil
            episode.downloadedDate = nil
            episode.fileSize = 0
          }
          try modelContext.save()
          downloadedAudioBytes = 0
        case .transcripts:
          try TranscriptStore.shared.deleteAll()
          transcriptsBytes = 0
        case .aiAnalysis:
          for analysis in try modelContext.fetch(FetchDescriptor<EpisodeAIAnalysis>()) {
            modelContext.delete(analysis)
          }
          try modelContext.save()
          aiAnalysisCount = 0
        }
      } catch {
        actionError = error.localizedDescription
      }
    }
  }

  /// Recreates the audio directory empty. A missing directory is already the
  /// goal, so only a real failure to remove or recreate it throws.
  @concurrent private static func removeDownloadedAudio() async throws {
    let fileManager = FileManager.default
    let audioDir = FileStorageManager.platformAudioDirectory(fileManager: fileManager)
    do {
      try fileManager.removeItem(at: audioDir)
    } catch let error as CocoaError where error.code == .fileNoSuchFile {}
    try fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)
  }
}

// Export/import actions, split from the struct body to keep it readable; same
// file, so they still reach the view's private state.
extension DataManagementView {
  // MARK: - Diagnostic Export

  private func exportDiagnosticReport() {
    // Gather library stats
    let podcastCount = (try? modelContext.fetchCount(
      FetchDescriptor<PodcastInfoModel>(predicate: #Predicate { $0.isSubscribed == true }))) ?? 0
    let episodeCount = (try? modelContext.fetchCount(FetchDescriptor<EpisodeDownloadModel>())) ?? 0

    // Build report
    var report: [String: Any] = [:]
    report["appVersion"] = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown"
    report["build"] = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unknown"
    report["osVersion"] = ProcessInfo.processInfo.operatingSystemVersionString
    report["date"] = Date.now.formatted(.iso8601)
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

    do {
      let jsonData = try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted)
      var fullReport = "=== Diagnostic Report ===\n\n" + (String(data: jsonData, encoding: .utf8) ?? "")

      // Append recent log file if available
      let logURL = URL.documentsDirectory.appending(path: "app_logs.txt")
      if let logs = try? String(contentsOf: logURL, encoding: .utf8) {
        fullReport += "\n\n=== Recent Logs ===\n" + logs.suffix(8000)
      }
      shareItem = try shareableFile(fullReport, named: "diagnostic_report.txt")
    } catch {
      actionError = error.localizedDescription
    }
  }

  // MARK: - Full Backup Export / Import

  private func exportFullBackup() {
    Task {
      do {
        let url = try await BackupService.shared.exportBackup()
        shareItem = ShareableOPML(url: url)
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
    do {
      let descriptor = FetchDescriptor<PodcastInfoModel>(
        predicate: #Predicate { $0.isSubscribed == true }
      )
      let podcasts = try modelContext.fetch(descriptor).map { $0.podcastInfo }
      shareItem = try shareableFile(OPMLParser.export(podcasts: podcasts), named: "subscriptions.opml")
    } catch {
      actionError = error.localizedDescription
    }
  }

  /// Writes to a temp file so ShareSheet/ShareLink can share it.
  private func shareableFile(_ contents: String, named name: String) throws -> ShareableOPML {
    let url = URL.temporaryDirectory.appending(path: name)
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return ShareableOPML(url: url)
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

  private func summaryContent(_ summary: BackupService.ImportSummary) -> some View {
    List {
      Section("Podcasts") {
        statRow("Subscribed", value: "\(summary.podcastsAdded) added · \(summary.podcastsMerged) already in library")
        if summary.podcastsFailed > 0 {
          statRow("Failed", value: "\(summary.podcastsFailed)").foregroundStyle(.red)
        }
      }
      Section("Episode History") {
        statRow("New episodes", value: "\(summary.episodesInserted)")
        statRow("Merged", value: "\(summary.episodesUpdated)")
      }
      Section("Other") {
        statRow("Queue items", value: "\(summary.queueReplaced)")
        statRow("AI analyses", value: "\(summary.analysesUpserted)")
        statRow("Settings", value: "\(summary.settingsApplied)")
      }
      if !summary.warnings.isEmpty {
        Section("Warnings") {
          ForEach(summary.warnings.indices, id: \.self) { idx in
            Text(summary.warnings[idx])
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private func statRow(_ label: LocalizedStringKey, value: LocalizedStringKey) -> some View {
    LabeledContent {
      Text(value)
    } label: {
      Text(label)
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
