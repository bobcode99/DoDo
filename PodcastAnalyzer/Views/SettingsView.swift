import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
  @State private var viewModel = SettingsViewModel()
  private var syncManager: BackgroundSyncManager { .shared }
  @Environment(\.modelContext) private var modelContext
  @Environment(\.openURL) private var openURL
  @State private var showAddFeedSheet = false
  @State private var showOPMLImporter = false
  @State private var opmlImportMessage: String?

  @AppStorage("allowCellularAutoDownload") private var allowCellularAutoDownload = false
  @AppStorage("allowAutoDownloadOnBattery") private var allowAutoDownloadOnBattery = false
  @AppStorage("episodeCacheLimit") private var episodeCacheLimit = 0

  private let cacheLimitOptions: [(label: String, value: Int)] = [
    ("Unlimited", 0),
    ("5 episodes", 5),
    ("10 episodes", 10),
    ("25 episodes", 25),
    ("50 episodes", 50)
  ]

  private let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
  private let skipIntervalOptions: [Int] = [5, 10, 15, 20, 30, 45, 60]

  var body: some View {
    List {
        // MARK: - Sync & Notifications Section
        Section {
          Toggle(isOn: Binding(get: { syncManager.isBackgroundSyncEnabled }, set: { syncManager.isBackgroundSyncEnabled = $0 })) {
            HStack {
              Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.blue)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Background Sync")
                if let lastSync = syncManager.lastSyncDate {
                  Text("Last: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }

          Toggle(isOn: Binding(get: { syncManager.isNotificationsEnabled }, set: { syncManager.isNotificationsEnabled = $0 })) {
            HStack {
              Image(systemName: "bell.badge")
                .foregroundStyle(.orange)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("New Episode Notifications")
                notificationStatusText
              }
            }
          }
          .disabled(!syncManager.isBackgroundSyncEnabled)

          Toggle(isOn: Binding(get: { viewModel.autoDownloadNewEpisodes }, set: { viewModel.setAutoDownloadNewEpisodes($0) })) {
            HStack {
              Image(systemName: "arrow.down.circle")
                .foregroundStyle(.purple)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Download New Episodes")
                Text("Automatically download new episodes from subscribed podcasts")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .disabled(!syncManager.isBackgroundSyncEnabled)

          if syncManager.isBackgroundSyncEnabled {
            Button(action: {
              Task {
                await syncManager.syncNow()
              }
            }) {
              HStack {
                Image(systemName: "arrow.clockwise")
                  .foregroundStyle(.green)
                  .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                  Text("Sync Now")
                  if syncManager.isSyncing && syncManager.syncProgressTotal > 0 {
                    Text("Syncing \(syncManager.syncProgressCurrent) of \(syncManager.syncProgressTotal)…")
                      .font(.caption2)
                      .foregroundStyle(.secondary)
                  }
                }
                Spacer()
                if syncManager.isSyncing {
                  ProgressView()
                    .scaleEffect(0.8)
                }
              }
            }
            .disabled(syncManager.isSyncing)
          }
        } header: {
          Text("Sync & Notifications")
        } footer: {
          if let error = syncManager.lastSyncError {
            Text("Last sync failed: \(error)")
              .foregroundStyle(.red)
          } else {
            Text("Automatically check for new episodes every 4 hours")
          }
        }

        // MARK: - Auto-Transcribe
        Section {
          NavigationLink(destination: AutoTranscribeManagementView()) {
            HStack {
              Image(systemName: "waveform.badge.plus")
                .foregroundStyle(.blue)
                .frame(width: 24)
              Text("Auto-transcribe Podcasts")
            }
          }
        } footer: {
          Text("Manage which podcasts auto-transcribe new episodes. Engine is resolved at run time: YAP server when configured, otherwise local (gated by charging).")
        }

        // MARK: - Auto-Download Section
        Section {
          Toggle(isOn: $allowCellularAutoDownload) {
            HStack {
              Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.blue)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Download on Cellular")
                Text("Allow auto-downloads when not on Wi-Fi")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }

          Toggle(isOn: $allowAutoDownloadOnBattery) {
            HStack {
              Image(systemName: "battery.50")
                .foregroundStyle(.green)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Download on Battery")
                Text("Allow auto-downloads when not charging")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }

          Picker(selection: $episodeCacheLimit) {
            ForEach(cacheLimitOptions, id: \.value) { option in
              Text(option.label).tag(option.value)
            }
          } label: {
            HStack {
              Image(systemName: "archivebox")
                .foregroundStyle(.orange)
                .frame(width: 24)
              Text("Episode Cache Limit")
            }
          }
        } header: {
          Text("Auto-Download")
        } footer: {
          Text("Per-podcast settings (Always / Never / Use Global) are in each podcast's context menu. Cache limit caps total auto-downloaded episodes; 0 = unlimited.")
        }

        // MARK: - Appearance Section
        Section {
          Toggle(isOn: Binding(
            get: { viewModel.showEpisodeArtwork },
            set: { viewModel.setShowEpisodeArtwork($0) }
          )) {
            HStack {
              Image(systemName: "photo")
                .foregroundStyle(.blue)
                .frame(width: 24)
              Text("Show Episode Artwork")
            }
          }
          Toggle(isOn: Binding(
            get: { viewModel.showForYouRecommendations },
            set: { viewModel.setShowForYouRecommendations($0) }
          )) {
            HStack {
              Image(systemName: "star.leadinghalf.filled")
                .foregroundStyle(.purple)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("For You Recommendations")
                Text("AI-powered episode suggestions on Home")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }

          Toggle(isOn: Binding(
            get: { viewModel.showTrendingEpisodes },
            set: { viewModel.setShowTrendingEpisodes($0) }
          )) {
            HStack {
              Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(.orange)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Trending Episodes")
                Text("Show trending episodes from top podcasts on Home")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }
        } header: {
          Text("Appearance")
        } footer: {
          Text("Hide artwork in episode lists to reduce memory usage")
        }

        // MARK: - Subscriptions Section
        Section {
          Button(action: { showAddFeedSheet = true }) {
            HStack {
              Image(systemName: "plus.circle.fill")
                .foregroundStyle(.blue)
                .font(.title2)
              Text("Add RSS Feed")
                .foregroundStyle(.primary)
              Spacer()
              Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.caption)
            }
          }

          Button(action: triggerImportShortcut) {
            HStack {
              Image(systemName: "arrow.down.app.fill")
                .foregroundStyle(.green)
                .font(.title2)
              Text("Import from Apple Podcasts")
                .foregroundStyle(.primary)
              Spacer()
              Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.caption)
            }
          }

          Button(action: { showOPMLImporter = true }) {
            HStack {
              Image(systemName: "doc.badge.arrow.up")
                .foregroundStyle(.blue)
                .font(.title2)
              VStack(alignment: .leading, spacing: 2) {
                Text("Import OPML File")
                  .foregroundStyle(.primary)
                if let msg = opmlImportMessage {
                  Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
              Spacer()
              Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.caption)
            }
          }
        } header: {
          Text("Subscriptions")
        } footer: {
          Text("Import from Apple Podcasts uses a Shortcut. Import OPML File picks any OPML or XML subscription export from another app.")
        }

        // MARK: - Playback Section
        Section {
          Picker(selection: $viewModel.defaultPlaybackSpeed) {
            ForEach(playbackSpeeds, id: \.self) { speed in
              Text(Formatters.formatSpeed(speed)).tag(speed)
            }
          } label: {
            HStack {
              Image(systemName: "gauge.with.dots.needle.33percent")
                .foregroundStyle(.blue)
                .frame(width: 24)
              Text("Default Speed")
            }
          }
          .onChange(of: viewModel.defaultPlaybackSpeed) { _, newValue in
            viewModel.setDefaultPlaybackSpeed(newValue)
          }

          Picker(selection: Binding(
            get: { viewModel.skipBackwardInterval },
            set: { viewModel.setSkipBackwardInterval($0) }
          )) {
            ForEach(skipIntervalOptions, id: \.self) { seconds in
              Text("\(seconds)s").tag(seconds)
            }
          } label: {
            HStack {
              Image(systemName: "gobackward")
                .foregroundStyle(.orange)
                .frame(width: 24)
              Text("Skip Back")
            }
          }

          Picker(selection: Binding(
            get: { viewModel.skipForwardInterval },
            set: { viewModel.setSkipForwardInterval($0) }
          )) {
            ForEach(skipIntervalOptions, id: \.self) { seconds in
              Text("\(seconds)s").tag(seconds)
            }
          } label: {
            HStack {
              Image(systemName: "goforward")
                .foregroundStyle(.orange)
                .frame(width: 24)
              Text("Skip Forward")
            }
          }

          Toggle(isOn: Binding(
            get: { viewModel.autoPlayNextEpisode },
            set: { viewModel.setAutoPlayNextEpisode($0) }
          )) {
            HStack {
              Image(systemName: "play.circle.fill")
                .foregroundStyle(.purple)
                .frame(width: 24)
              Text("Auto-Play Next Episode")
            }
          }
        } header: {
          Text("Playback")
        } footer: {
          Text("Skip intervals also apply to lock screen and headphone controls. Auto-play continues from the Up Next queue when it would otherwise stop.")
        }

        // MARK: - Region Section
        Section {
          Picker(selection: $viewModel.selectedRegion) {
            ForEach(Constants.podcastRegions, id: \.code) { region in
              Text(region.name).tag(region.code)
            }
          } label: {
            HStack {
              Image(systemName: "globe")
                .foregroundStyle(.blue)
                .frame(width: 24)
              Text("Default Region")
            }
          }
          .onChange(of: viewModel.selectedRegion) { _, newValue in
            viewModel.setSelectedRegion(newValue)
          }
        } header: {
          Text("Discovery")
        } footer: {
          Text("Region for browsing top podcasts on Home")
        }

        // MARK: - Translation Section
        Section {
          Picker(selection: Binding(
            get: { SubtitleSettingsManager.shared.targetLanguage },
            set: { SubtitleSettingsManager.shared.targetLanguage = $0 }
          )) {
            ForEach(TranslationTargetLanguage.allCases, id: \.self) { language in
              Text(language.displayName).tag(language)
            }
          } label: {
            HStack {
              Image(systemName: "translate")
                .foregroundStyle(.blue)
                .frame(width: 24)
              Text("Default Translation Language")
            }
          }
          Toggle(isOn: Binding(
            get: { SubtitleSettingsManager.shared.autoTranslateOnLoad },
            set: { SubtitleSettingsManager.shared.autoTranslateOnLoad = $0 }
          )) {
            HStack {
              Image(systemName: "text.bubble")
                .foregroundStyle(.purple)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Translate on Load")
                Text("Translate transcripts when loaded")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }
        } header: {
          Text("Translation")
        } footer: {
          Text("Default target language for translating transcripts and episode descriptions")
        }

        // MARK: - Transcript Section
        Section {
          // Engine picker
          Picker(selection: Binding(
            get: { viewModel.selectedTranscriptEngine },
            set: { viewModel.setTranscriptEngine($0) }
          )) {
            ForEach(TranscriptEngine.allCases) { engine in
              Text(engine.displayName).tag(engine)
            }
          } label: {
            HStack {
              Image(systemName: "cpu")
                .foregroundStyle(.indigo)
                .frame(width: 24)
              Text("Engine")
            }
          }

          // Language picker (applies to both engines)
          Picker(selection: $viewModel.selectedTranscriptLocale) {
            ForEach(SettingsViewModel.locales(for: viewModel.selectedTranscriptEngine)) { locale in
              Text(locale.name).tag(locale.id)
            }
          } label: {
            HStack {
              Image(systemName: "globe")
                .foregroundStyle(.blue)
                .frame(width: 24)
              Text("Language")
            }
          }
          .onChange(of: viewModel.selectedTranscriptLocale) { _, newValue in
            viewModel.setSelectedTranscriptLocale(newValue)
          }

          // Apple Speech model status (only shown when engine = appleSpeech)
          if viewModel.selectedTranscriptEngine == .appleSpeech {
            HStack {
              Image(systemName: "waveform")
                .foregroundStyle(.blue)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Speech Model")
                transcriptStatusText
              }
              Spacer()
              transcriptActionButton
            }
          }

          Toggle(isOn: Binding(
            get: { SubtitleSettingsManager.shared.autoGenerateTranscripts },
            set: { SubtitleSettingsManager.shared.autoGenerateTranscripts = $0 }
          )) {
            HStack {
              Image(systemName: "waveform")
                .foregroundStyle(.orange)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Generate Transcripts")
                Text("Generate when episodes are downloaded")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }
        } header: {
          Text("Transcript")
        } footer: {
          switch viewModel.selectedTranscriptEngine {
          case .whisper:
            Text("Whisper models are downloaded once and stored on device. Larger models produce more accurate transcripts.")
          case .yapServer:
            Text("Yap Server uses a local HTTP service wrapping Apple Speech. No model download required.")
          case .appleSpeech:
            Text("Download the Apple Speech model for your preferred language. Each podcast uses its own language from the RSS feed.")
          }
        }

        // MARK: - Whisper Models Section (only shown when Whisper engine selected)
        if viewModel.selectedTranscriptEngine == .whisper {
          WhisperModelsSection()
        }

        // MARK: - Yap Server Section (only shown when Yap Server engine selected)
        if viewModel.selectedTranscriptEngine == .yapServer {
          YapServerSection()
        }

        // MARK: - AI Settings Section
        Section {
          NavigationLink {
            AISettingsView()
          } label: {
            HStack {
              Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .frame(width: 24)
              Text("AI Settings")
              Spacer()
              if AISettingsManager.shared.hasConfiguredProvider {
                Text(AISettingsManager.shared.selectedProvider.displayName)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              } else {
                Text("Not configured")
                  .font(.caption)
                  .foregroundStyle(.orange)
              }
            }
          }
        } header: {
          Text("AI Analysis")
        } footer: {
          Text("Configure cloud AI providers (OpenAI, Claude, Gemini, Grok) for transcript analysis")
        }

        // MARK: - Insights Section
        Section {
          NavigationLink {
            ListeningStatsView()
          } label: {
            HStack {
              Image(systemName: "chart.bar.fill")
                .foregroundStyle(.indigo)
                .frame(width: 24)
              Text("Listening Stats")
            }
          }
        } header: {
          Text("Insights")
        } footer: {
          Text("View your listening history, top shows, and trends")
        }

        // MARK: - Data Management Section
        Section {
          NavigationLink {
            DataManagementView()
          } label: {
            HStack {
              Image(systemName: "externaldrive")
                .foregroundStyle(.gray)
                .frame(width: 24)
              Text("Data Management")
            }
          }
        } header: {
          Text("Storage")
        } footer: {
          Text("Manage cached images, downloads, transcripts, and AI analysis data")
        }

        // MARK: - About Section
        Section {
          HStack {
            Image(systemName: "info.circle")
              .foregroundStyle(.blue)
              .frame(width: 24)
            Text("Version")
            Spacer()
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("About")
        }

        #if DEBUG
        // MARK: - Debug Section
        Section {
          NavigationLink {
            ShortcutsDebugView()
          } label: {
            HStack {
              Image(systemName: "ladybug.fill")
                .foregroundStyle(.red)
                .frame(width: 24)
              Text("Shortcuts Debug")
            }
          }
        } header: {
          Text("Debug")
        } footer: {
          Text("Validate the SaveAnalysisResultIntent App Intent and observe the notification flow.")
        }
        #endif

        // MARK: - Language Section
        Section {
          Picker(selection: Binding(
            get: { LanguageManager.shared.appLanguage },
            set: { LanguageManager.shared.appLanguage = $0 }
          )) {
            ForEach(LanguageManager.availableLanguages) { language in
              Text(language.displayName).tag(language.id)
            }
          } label: {
            HStack {
              Image(systemName: "character.bubble")
                .foregroundStyle(.teal)
                .frame(width: 24)
              Text("App Language")
            }
          }
          #if os(iOS)
          .pickerStyle(.menu)
          #endif
        } header: {
          Text("Language")
        } footer: {
          Text("Choose the language for the app interface. 'System Default' follows your device language.")
        }
      }
      #if os(iOS)
      .listStyle(.insetGrouped)
      #else
      .listStyle(.sidebar)
      #endif
      .navigationTitle("Settings")
      .platformToolbarTitleDisplayMode()
      .sheet(isPresented: $showAddFeedSheet) {
        AddFeedView(viewModel: viewModel, modelContext: modelContext) {
          showAddFeedSheet = false
        }
      }
      .fileImporter(
        isPresented: $showOPMLImporter,
        allowedContentTypes: [.xml, UTType(filenameExtension: "opml") ?? .xml],
        allowsMultipleSelection: false
      ) { result in
        handleOPMLImport(result)
      }
      .onAppear {
        viewModel.loadFeeds(modelContext: modelContext)
        viewModel.checkTranscriptModelStatus()
        WhisperModelManager.shared.checkAllModelStatuses()
      }
  }

  private func triggerImportShortcut() {
    if let url = URL(string: "shortcuts://run-shortcut?name=ApplePodcast%20To%20PodcastAnalyzer") {
      openURL(url)
    }
  }

  private func handleOPMLImport(_ result: Result<[URL], Error>) {
    switch result {
    case .failure:
      opmlImportMessage = "Import cancelled"
    case .success(let urls):
      guard let fileURL = urls.first else { return }
      let accessing = fileURL.startAccessingSecurityScopedResource()
      defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
      guard let data = try? Data(contentsOf: fileURL) else {
        opmlImportMessage = "Could not read file"
        return
      }
      let feedURLs = OPMLParser.parse(data: data)
      guard !feedURLs.isEmpty else {
        opmlImportMessage = "No feeds found in file"
        return
      }
      opmlImportMessage = "Importing \(feedURLs.count) podcast\(feedURLs.count == 1 ? "" : "s")…"
      let manager = PodcastImportManager.shared
      manager.setModelContext(modelContext)
      Task {
        await manager.importPodcasts(from: feedURLs)
        await MainActor.run {
          opmlImportMessage = "Imported \(feedURLs.count) podcast\(feedURLs.count == 1 ? "" : "s")"
        }
      }
    }
  }

  // MARK: - Notification Status Text

  @ViewBuilder
  private var notificationStatusText: some View {
    switch syncManager.notificationPermissionStatus {
    case .authorized:
      Text("Enabled")
        .font(.caption2)
        .foregroundStyle(.green)
    case .denied:
      Text("Denied - Enable in Settings")
        .font(.caption2)
        .foregroundStyle(.red)
    case .notDetermined:
      Text("Permission required")
        .font(.caption2)
        .foregroundStyle(.orange)
    default:
      Text("Unknown")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Transcript Status Views

  @ViewBuilder
  private var transcriptStatusText: some View {
    switch viewModel.transcriptModelStatus {
    case .checking:
      Text("Checking...")
        .font(.caption)
        .foregroundStyle(.secondary)
    case .notDownloaded:
      Text("Not installed")
        .font(.caption)
        .foregroundStyle(.orange)
    case .downloading(let progress):
      Text("Downloading \(Int(progress * 100))%")
        .font(.caption)
        .foregroundStyle(.blue)
    case .ready:
      Text("Ready")
        .font(.caption)
        .foregroundStyle(.green)
    case .error(let message):
      Text(message)
        .font(.caption)
        .foregroundStyle(.red)
        .lineLimit(1)
    case .simulatorNotSupported:
      Text("Requires physical device")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var transcriptActionButton: some View {
    switch viewModel.transcriptModelStatus {
    case .checking:
      ProgressView()
        .scaleEffect(0.8)
    case .notDownloaded, .error:
      Button("Download") {
        viewModel.downloadTranscriptModel()
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
    case .downloading(let progress):
      HStack(spacing: 8) {
        ProgressView(value: progress)
          .frame(width: 60)
        Button {
          viewModel.cancelTranscriptDownload()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    case .ready:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .simulatorNotSupported:
      Image(systemName: "desktopcomputer")
        .foregroundStyle(.secondary)
    }
  }

}

#Preview {
  SettingsView()
}
