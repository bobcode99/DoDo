import SwiftData
import SwiftUI
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

  private let playbackSpeeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

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
              Image(systemName: "square.and.arrow.down.fill")
                .foregroundStyle(.green)
                .font(.title2)
              Text("Import Podcasts")
                .foregroundStyle(.primary)
              Spacer()
              Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
                .font(.caption)
            }
          }
        } header: {
          Text("Subscriptions")
        } footer: {
          Text("Add by RSS URL or import an OPML file exported from Apple Podcasts")
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
          Text("When enabled, the top-ranked unplayed episode from Up Next will play when the queue is empty")
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
            ForEach(SettingsViewModel.availableTranscriptLocales) { locale in
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
          Text(viewModel.selectedTranscriptEngine == .whisper
            ? "Whisper models are downloaded once and stored on device. Larger models produce more accurate transcripts."
            : "Download the Apple Speech model for your preferred language. Each podcast uses its own language from the RSS feed."
          )
        }

        // MARK: - Whisper Models Section (only shown when Whisper engine selected)
        if viewModel.selectedTranscriptEngine == .whisper {
          WhisperModelsSection()
        }

        // MARK: - Background Transcription Section
        Section {
          Toggle(isOn: Binding(
            get: { BackgroundTranscriptProcessor.shared.isEnabled },
            set: { BackgroundTranscriptProcessor.shared.isEnabled = $0 }
          )) {
            HStack {
              Image(systemName: "bolt.fill")
                .foregroundStyle(.yellow)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Auto-Transcribe While Charging")
                Text("Transcribe downloaded episodes when plugged in")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }

          if BackgroundTranscriptProcessor.shared.isProcessing {
            HStack {
              Image(systemName: "waveform")
                .foregroundStyle(.blue)
                .frame(width: 24)
              VStack(alignment: .leading, spacing: 2) {
                Text("Processing")
                Text("\(BackgroundTranscriptProcessor.shared.processedCount) of \(BackgroundTranscriptProcessor.shared.pendingCount) queued")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button("Stop") {
                BackgroundTranscriptProcessor.shared.cancelProcessing()
              }
              .font(.caption)
              .foregroundStyle(.red)
            }
          }

          Button {
            BackgroundTranscriptProcessor.shared.processAll(podcasts: viewModel.podcastInfoModelList)
          } label: {
            HStack {
              Image(systemName: "arrow.clockwise")
                .foregroundStyle(.green)
                .frame(width: 24)
              Text("Process All Now")
            }
          }
          .disabled(BackgroundTranscriptProcessor.shared.isProcessing)
        } header: {
          Text("Background Transcription")
        } footer: {
          Text("Automatically generate transcripts for all downloaded episodes when your device is charging")
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
