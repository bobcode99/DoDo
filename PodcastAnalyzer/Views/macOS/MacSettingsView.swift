//
//  MacSettingsView.swift
//  PodcastAnalyzer
//
//  macOS-specific settings view for Preferences window (Cmd+,)
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacSettingsView: View {
  private enum SettingsTab: Hashable, CaseIterable {
    case general, appearance, sync, playback, transcript, ai, mcp, storage

    var title: LocalizedStringKey {
      switch self {
      case .general: "General"
      case .appearance: "Appearance"
      case .sync: "Sync"
      case .playback: "Playback"
      case .transcript: "Transcript"
      case .ai: "AI"
      case .mcp: "MCP"
      case .storage: "Storage"
      }
    }

    var systemImage: String {
      switch self {
      case .general: "gearshape"
      case .appearance: "paintbrush"
      case .sync: "arrow.triangle.2.circlepath"
      case .playback: "play.circle"
      case .transcript: "text.bubble"
      case .ai: "sparkles"
      case .mcp: "network"
      case .storage: "internaldrive"
      }
    }
  }

  @State private var selection: SettingsTab = .general
  @State private var viewModel = SettingsViewModel()

  var body: some View {
    TabView(selection: $selection) {
      ForEach(SettingsTab.allCases, id: \.self) { tab in
        Tab(tab.title, systemImage: tab.systemImage, value: tab) {
          tabContent(for: tab)
        }
      }
    }
    .frame(maxWidth: 560, minHeight: 300)
    .scenePadding()
  }

  @ViewBuilder
  private func tabContent(for tab: SettingsTab) -> some View {
    switch tab {
    case .general: GeneralSettingsTab(viewModel: viewModel)
    case .appearance: AppearanceSettingsTab(viewModel: viewModel)
    case .sync: SyncSettingsTab(viewModel: viewModel)
    case .playback: PlaybackSettingsTab(viewModel: viewModel)
    case .transcript: TranscriptSettingsTab(viewModel: viewModel)
    case .ai: AISettingsTab()
    case .mcp: MacMCPSettingsView()
    case .storage: StorageSettingsTab()
    }
  }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
  let viewModel: SettingsViewModel
  @State private var showAddFeedSheet = false
  @State private var showListeningStats = false
  @State private var showImportInstructions = false
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    @Bindable var viewModel = viewModel

    Form {
      Section {
        Button("Add RSS Feed") {
          showAddFeedSheet = true
        }
        Button("Import Podcasts…") {
          showImportInstructions = true
        }
      } header: {
        Text("Subscriptions")
      } footer: {
        Text("Add by RSS URL or import an OPML file exported from Apple Podcasts.")
      }

      Section {
        Picker("Default Region", selection: $viewModel.selectedRegion) {
          ForEach(Constants.podcastRegions, id: \.code) { region in
            Text(region.name).tag(region.code)
          }
        }
        .onChange(of: viewModel.selectedRegion) { _, newValue in
          viewModel.setSelectedRegion(newValue)
        }
      } header: {
        Text("Discovery")
      } footer: {
        Text("Region for browsing top podcasts on Home.")
      }

      Section {
        Button("Listening Stats") {
          showListeningStats = true
        }
      } header: {
        Text("Insights")
      } footer: {
        Text("View your listening history, top shows, and trends.")
      }

      Section {
        Picker("App Language", selection: Binding(
          get: { LanguageManager.shared.appLanguage },
          set: { LanguageManager.shared.appLanguage = $0 }
        )) {
          ForEach(LanguageManager.availableLanguages) { language in
            Text(language.displayName).tag(language.id)
          }
        }
      } header: {
        Text("Language")
      } footer: {
        Text("Choose the language for the app interface. 'System Default' follows your device language.")
      }

      Section {
        LabeledContent("Version") {
          Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("About")
      }
    }
    .formStyle(.grouped)
    .padding()
    .sheet(isPresented: $showAddFeedSheet) {
      AddFeedView(viewModel: viewModel, modelContext: modelContext) {
        showAddFeedSheet = false
      }
    }
    .sheet(isPresented: $showListeningStats) {
      NavigationStack {
        ListeningStatsView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Close") { showListeningStats = false }
            }
          }
      }
      .frame(minWidth: 500, minHeight: 400)
    }
    .sheet(isPresented: $showImportInstructions) {
      NavigationStack {
        ScrollView {
          ImportShortcutInstructionsView()
            .padding()
        }
        .navigationTitle("Import from Apple Podcasts")
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { showImportInstructions = false }
          }
        }
      }
      .frame(minWidth: 440, minHeight: 480)
    }
    .onAppear {
      viewModel.loadFeeds(modelContext: modelContext)
    }
  }
}

// MARK: - Appearance Settings Tab

struct AppearanceSettingsTab: View {
  let viewModel: SettingsViewModel

  var body: some View {
    @Bindable var viewModel = viewModel

    Form {
      Section {
        Toggle("Show Episode Artwork", isOn: $viewModel.showEpisodeArtwork)
          .onChange(of: viewModel.showEpisodeArtwork) { _, newValue in
            viewModel.setShowEpisodeArtwork(newValue)
          }

        Toggle("For You Recommendations", isOn: $viewModel.showForYouRecommendations)
          .onChange(of: viewModel.showForYouRecommendations) { _, newValue in
            viewModel.setShowForYouRecommendations(newValue)
          }

        Toggle("Trending Episodes", isOn: $viewModel.showTrendingEpisodes)
          .onChange(of: viewModel.showTrendingEpisodes) { _, newValue in
            viewModel.setShowTrendingEpisodes(newValue)
          }
      } header: {
        Text("Episode Lists")
      } footer: {
        Text("Show AI-powered episode suggestions and trending episodes on Home. Hide artwork to reduce memory usage.")
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}

// MARK: - Sync Settings Tab

struct SyncSettingsTab: View {
  let viewModel: SettingsViewModel
  @AppStorage("allowAutoDownloadOnBattery") private var allowAutoDownloadOnBattery = false
  @AppStorage("episodeCacheLimit") private var episodeCacheLimit = 0

  private let cacheLimitOptions: [(label: String, value: Int)] = [
    ("Unlimited", 0),
    ("5 episodes", 5),
    ("10 episodes", 10),
    ("25 episodes", 25),
    ("50 episodes", 50)
  ]

  var body: some View {
    @Bindable var syncManager = BackgroundSyncManager.shared
    @Bindable var viewModel = viewModel

    Form {
      Section {
        Toggle("Enable Background Sync", isOn: $syncManager.isBackgroundSyncEnabled)

        if syncManager.isBackgroundSyncEnabled {
          Toggle("New Episode Notifications", isOn: $syncManager.isNotificationsEnabled)

          Toggle("Auto-Download New Episodes", isOn: $viewModel.autoDownloadNewEpisodes)
            .onChange(of: viewModel.autoDownloadNewEpisodes) { _, newValue in
              viewModel.setAutoDownloadNewEpisodes(newValue)
            }

          if let lastSync = syncManager.lastSyncDate {
            LabeledContent("Last Sync") {
              Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
            }
          }

          Button("Sync Now") {
            Task {
              await syncManager.syncNow()
            }
          }
          .disabled(syncManager.isSyncing)
        }
      } header: {
        Text("Sync Settings")
      } footer: {
        Text("Automatically check for new episodes periodically while the app is running.")
      }

      Section {
        Toggle(isOn: $allowAutoDownloadOnBattery) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Download on Battery")
            Text("Allow auto-downloads when the Mac isn't plugged in")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Picker("Episode Cache Limit", selection: $episodeCacheLimit) {
          ForEach(cacheLimitOptions, id: \.value) { option in
            Text(option.label).tag(option.value)
          }
        }
      } header: {
        Text("Auto-Download")
      } footer: {
        Text("Per-podcast settings (Always / Never / Use Global) are in each podcast's context menu. Cache limit caps total auto-downloaded episodes; 0 = unlimited.")
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}

// MARK: - Playback Settings Tab

struct PlaybackSettingsTab: View {
  let viewModel: SettingsViewModel
  private let playbackSpeeds: [Float] = Formatters.playbackSpeeds
  private let skipIntervalOptions: [Int] = [5, 10, 15, 20, 30, 45, 60]

  var body: some View {
    @Bindable var viewModel = viewModel

    Form {
      Section {
        Picker("Default Playback Speed", selection: $viewModel.defaultPlaybackSpeed) {
          ForEach(playbackSpeeds, id: \.self) { speed in
            Text(Formatters.formatSpeed(speed)).tag(speed)
          }
        }
        .onChange(of: viewModel.defaultPlaybackSpeed) { _, newValue in
          viewModel.setDefaultPlaybackSpeed(newValue)
        }

        Picker("Skip Back", selection: Binding(
          get: { viewModel.skipBackwardInterval },
          set: { viewModel.setSkipBackwardInterval($0) }
        )) {
          ForEach(skipIntervalOptions, id: \.self) { seconds in
            Text("\(seconds)s").tag(seconds)
          }
        }

        Picker("Skip Forward", selection: Binding(
          get: { viewModel.skipForwardInterval },
          set: { viewModel.setSkipForwardInterval($0) }
        )) {
          ForEach(skipIntervalOptions, id: \.self) { seconds in
            Text("\(seconds)s").tag(seconds)
          }
        }

        Toggle("Auto-Play Next Episode", isOn: $viewModel.autoPlayNextEpisode)
          .onChange(of: viewModel.autoPlayNextEpisode) { _, newValue in
            viewModel.setAutoPlayNextEpisode(newValue)
          }
      } header: {
        Text("Playback")
      } footer: {
        Text("Skip intervals apply to in-app controls and lock screen/headphone buttons.")
      }
    }
    .formStyle(.grouped)
    .padding()
  }

}

// MARK: - Transcript Settings Tab

struct TranscriptSettingsTab: View {
  let viewModel: SettingsViewModel
  @State private var showAutoTranscribeManagement = false
  @State private var showTranscriptionContext = false

  var body: some View {
    @Bindable var viewModel = viewModel
    @Bindable var subtitleSettings = SubtitleSettingsManager.shared

    Form {
      // MARK: Engine selection
      Section {
        Picker("Engine", selection: $viewModel.selectedTranscriptEngine)  {
          ForEach(TranscriptEngine.allCases) { engine in
            Text(engine.displayName).tag(engine)
          }
        }
        .onChange(of: viewModel.selectedTranscriptEngine) { _, newValue in
          viewModel.setTranscriptEngine(newValue)
        }

        Picker("Language", selection: $viewModel.selectedTranscriptLocale) {
          ForEach(SettingsViewModel.availableTranscriptLocales) { locale in
            Text(locale.name).tag(locale.id)
          }
        }
        .onChange(of: viewModel.selectedTranscriptLocale) { _, newValue in
          viewModel.setSelectedTranscriptLocale(newValue)
        }

        // Apple Speech model status row
        if viewModel.selectedTranscriptEngine == .appleSpeech {
          LabeledContent("Speech Model Status") {
            AppleSpeechStatusView(viewModel: viewModel)
          }
        }
      } header: {
        Text("Transcript Settings")
      } footer: {
        Text(viewModel.selectedTranscriptEngine == .whisper
          ? "\(viewModel.selectedTranscriptEngine.description)"
          : "Download the Apple Speech model for your preferred language. Each podcast uses its own language from the RSS feed."
        )
      }

      // MARK: Translation
      Section {
        Picker("Default Translation Language", selection: $subtitleSettings.targetLanguage) {
          ForEach(TranslationTargetLanguage.allCases, id: \.self) { language in
            Text(language.displayName).tag(language)
          }
        }

        Toggle("Auto-Translate on Load", isOn: $subtitleSettings.autoTranslateOnLoad)
      } header: {
        Text("Translation")
      } footer: {
        Text("Default target language for translating transcripts and episode descriptions.")
      }

      // MARK: Auto-generate
      Section {
        Toggle("Auto-Generate Transcripts", isOn: $subtitleSettings.autoGenerateTranscripts)

        Toggle("Detect Music", isOn: $subtitleSettings.enableMusicDetection)
        if subtitleSettings.enableMusicDetection {
          Picker("Music Sensitivity", selection: $subtitleSettings.musicDetectionSensitivity) {
            ForEach(MusicDetectionSensitivity.allCases, id: \.self) { level in
              Text(level.displayName).tag(level)
            }
          }
        }

        Toggle("Split Long Audio", isOn: $subtitleSettings.splitLongAudio)

        Button {
          showTranscriptionContext = true
        } label: {
          HStack {
            Label("Transcription Context", systemImage: "character.book.closed")
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        Button {
          showAutoTranscribeManagement = true
        } label: {
          HStack {
            Label("Auto-transcribe Podcasts", systemImage: "waveform.badge.plus")
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundStyle(.tertiary)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      } header: {
        Text("Automation")
      } footer: {
        Text("Detect Music marks music ranges as [♪ Music] instead of transcribing them. Split Long Audio transcribes in parallel parts (faster on Apple Speech); turn off for one single-pass run. Transcription Context adds per-podcast names & jargon to improve accuracy. Auto-transcribe resolves the engine at run time: YAP server when configured, otherwise local (gated by charging).")
      }

      // MARK: Whisper models list
      if viewModel.selectedTranscriptEngine == .whisper {
        Section {
          ForEach(WhisperModelVariant.allCases) { variant in
            MacWhisperModelRow(variant: variant)
          }
        } header: {
          Text("Whisper Models")
        } footer: {
          Text("On macOS, Medium and Large v3 Turbo offer the best accuracy. Models are stored in ~/Library/Caches.")
        }
      }

      // MARK: YAP server config
      if viewModel.selectedTranscriptEngine == .yapServer {
        YapServerSection()
      }
    }
    .formStyle(.grouped)
    .padding()
    .frame(minHeight: minTranscriptTabHeight(for: viewModel.selectedTranscriptEngine))
    .onAppear {
      viewModel.checkTranscriptModelStatus()
      WhisperModelManager.shared.checkAllModelStatuses()
    }
    .sheet(isPresented: $showAutoTranscribeManagement) {
      NavigationStack {
        AutoTranscribeManagementView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Done") { showAutoTranscribeManagement = false }
            }
          }
      }
      .frame(minWidth: 520, minHeight: 480)
    }
    .sheet(isPresented: $showTranscriptionContext) {
      NavigationStack {
        TranscriptContextManagementView()
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Done") { showTranscriptionContext = false }
            }
          }
      }
      .frame(minWidth: 520, minHeight: 480)
    }
  }

  private func minTranscriptTabHeight(for engine: TranscriptEngine) -> CGFloat {
    switch engine {
    case .whisper: 500
    case .yapServer: 360
    default: 300
    }
  }
}

// MARK: - Apple Speech Status View

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
          .buttonStyle(.borderedProminent).controlSize(.small)
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
          .buttonStyle(.borderedProminent).controlSize(.small)
      }
    case .simulatorNotSupported:
      Text("Requires physical device").foregroundStyle(.secondary)
    }
  }
}

// MARK: - macOS Whisper Model Row

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
        .buttonStyle(.borderedProminent).controlSize(.small)
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
          .buttonStyle(.borderedProminent).controlSize(.small)
      }
      .help(message)
    }
  }
}

// MARK: - AI Settings Tab

/// Renders the AI provider configuration UI inline in the Settings tab
/// instead of pushing a sheet — keeps every Settings pane on one page.
struct AISettingsTab: View {
  var body: some View {
    AISettingsView()
  }
}

// MARK: - Storage Settings Tab

struct StorageSettingsTab: View {
  @Environment(\.modelContext) private var modelContext

  @State private var imageCacheSize: String = "Calculating..."
  @State private var downloadedAudioSize: String = "Calculating..."
  @State private var transcriptsSize: String = "Calculating..."
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
          size: imageCacheSize,
          isClearing: isClearingData && clearingMessage == "cache"
        ) {
          showClearCacheAlert = true
        }

        storageRow(
          icon: "arrow.down.circle.fill",
          iconColor: .green,
          title: "Downloaded Episodes",
          size: downloadedAudioSize,
          isClearing: isClearingData && clearingMessage == "downloads",
          isDestructive: true
        ) {
          showClearDownloadsAlert = true
        }

        storageRow(
          icon: "text.bubble",
          iconColor: .blue,
          title: "Transcripts",
          size: transcriptsSize,
          isClearing: isClearingData && clearingMessage == "transcripts",
          isDestructive: true
        ) {
          showClearTranscriptsAlert = true
        }

        storageRow(
          icon: "sparkles",
          iconColor: .purple,
          title: "AI Analysis Data",
          size: "\(aiAnalysisCount) analyses",
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
    .onAppear {
      calculateStorageInfo()
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
    title: String,
    size: String,
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
        Text(size)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if isClearing {
        ProgressView()
          .scaleEffect(0.7)
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

  private func calculateStorageInfo() {
    Task {
      let cacheSize = await calculateImageCacheSize()
      imageCacheSize = formatBytes(cacheSize)

      let audioSize = await calculateDownloadedAudioSize()
      downloadedAudioSize = formatBytes(audioSize)

      let captionsSize = await calculateTranscriptsSize()
      transcriptsSize = formatBytes(captionsSize)

      let analysisCount = countAIAnalyses()
      aiAnalysisCount = analysisCount
    }
  }

  private func calculateImageCacheSize() async -> Int64 {
    ImageCacheUtility.dataCacheTotalSize()
  }

  private nonisolated static func enumerateDirectorySize(at subpath: String, in searchPath: FileManager.SearchPathDirectory) -> Int64 {
    let fileManager = FileManager.default
    let baseDir = fileManager.urls(for: searchPath, in: .userDomainMask)[0]
    let targetDir = baseDir.appendingPathComponent(subpath)

    guard let enumerator = fileManager.enumerator(at: targetDir, includingPropertiesForKeys: [.fileSizeKey])
    else { return 0 }

    var totalSize: Int64 = 0
    for case let fileURL as URL in enumerator {
      if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
        totalSize += Int64(size)
      }
    }
    return totalSize
  }

  private func calculateDownloadedAudioSize() async -> Int64 {
    await FileStorageManager.shared.calculateTotalAudioSize()
  }

  private func calculateTranscriptsSize() async -> Int64 {
    // Reuse the same nonisolated helper for Captions directory
    Self.enumerateDirectorySize(at: "Captions", in: .documentDirectory)
  }

  private func countAIAnalyses() -> Int {
    let descriptor = FetchDescriptor<EpisodeAIAnalysis>()
    return (try? modelContext.fetchCount(descriptor)) ?? 0
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  // MARK: - Clear Actions

  private func clearImageCache() {
    isClearingData = true
    clearingMessage = "cache"

    Task {
      ImageCacheUtility.clearAllCache()
      isClearingData = false
      clearingMessage = ""
      imageCacheSize = "0 bytes"
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
        try? modelContext.save()
      }

      await FileStorageManager.shared.clearAllAudioFiles()

      isClearingData = false
      clearingMessage = ""
      downloadedAudioSize = "0 bytes"
    }
  }

  private func clearAllTranscripts() {
    isClearingData = true
    clearingMessage = "transcripts"

    Task {
      let descriptor = FetchDescriptor<EpisodeDownloadModel>(
        predicate: #Predicate { $0.captionPath != nil }
      )

      if let episodesWithCaptions = try? modelContext.fetch(descriptor) {
        for episode in episodesWithCaptions {
          episode.captionPath = nil
        }
        try? modelContext.save()
      }

      await FileStorageManager.shared.clearAllCaptionFiles()

      isClearingData = false
      clearingMessage = ""
      transcriptsSize = "0 bytes"
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

      let tagsDescriptor = FetchDescriptor<EpisodeQuickTagsModel>()
      if let tags = try? modelContext.fetch(tagsDescriptor) {
        for tag in tags {
          modelContext.delete(tag)
        }
        try? modelContext.save()
      }

      isClearingData = false
      clearingMessage = ""
      aiAnalysisCount = 0
    }
  }
}

#Preview {
  MacSettingsView()
}

#endif
