//
//  SettingsDetailScreens.swift
//  PodcastAnalyzer
//
//  The screens behind the Settings category list. Splitting one 13-section
//  scroll into short, single-topic screens is the point: each one fits without
//  scrolling, so a setting is found by picking a category rather than by
//  reading every row.
//
//  Per-row caption text was dropped in favour of section footers — a caption
//  under every control is noise when the whole screen is one topic.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Sync & Notifications

struct SyncSettingsScreen: View {
  private var syncManager: BackgroundSyncManager { .shared }
  @State private var cloud = CloudSyncStatus.shared

  // The three models in the CloudKit-mirrored configuration
  // (PodcastAnalyzerApp.swift). Counted so "is it actually syncing?" has an
  // answer that does not depend on opening another device.
  @Query private var progressRows: [PlaybackProgressModel]
  @Query private var subscriptionRows: [SubscribedPodcastModel]
  @Query private var queueRows: [QueueItemModel]

  var body: some View {
    List {
      Section {
        Toggle(isOn: Binding(
          get: { syncManager.isBackgroundSyncEnabled },
          set: { syncManager.isBackgroundSyncEnabled = $0 }
        )) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Background Sync")
            if let lastSync = syncManager.lastSyncDate {
              Text("Last checked \(Formatters.formatDate(lastSync, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }

        Toggle(isOn: Binding(
          get: { syncManager.isNotificationsEnabled },
          set: { syncManager.isNotificationsEnabled = $0 }
        )) {
          VStack(alignment: .leading, spacing: 2) {
            Text("New Episode Notifications")
            notificationStatusText
          }
        }
        .disabled(!syncManager.isBackgroundSyncEnabled)
      } footer: {
        if let error = syncManager.lastSyncError {
          Text("Last sync failed: \(error)")
            .foregroundStyle(.red)
        } else {
          Text("Checks your subscriptions for new episodes every 4 hours.")
        }
      }

      if syncManager.isBackgroundSyncEnabled {
        Section {
          Button {
            Task { await syncManager.syncNow() }
          } label: {
            HStack {
              Text("Check for New Episodes")
              Spacer()
              if syncManager.isSyncing {
                if syncManager.syncProgressTotal > 0 {
                  Text("\(syncManager.syncProgressCurrent) of \(syncManager.syncProgressTotal)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                ProgressView().scaleEffect(0.8)
              }
            }
          }
          .disabled(syncManager.isSyncing)
        }
      }
      iCloudSection
    }
    .navigationTitle("Sync & Notifications")
    .platformToolbarTitleDisplayMode()
    .task { await cloud.refreshAccountStatus() }
  }

  // MARK: - iCloud

  /// Separate from background sync above: that one polls RSS feeds, this one
  /// mirrors playback progress, subscriptions and Up Next between devices —
  /// including the watch, which has no other source of data.
  @ViewBuilder
  private var iCloudSection: some View {
    Section("iCloud") {
      LabeledContent("Account") {
        accountText.foregroundStyle(accountColor)
      }

      activityRow("Last Download", cloud.lastImport)
      activityRow("Last Upload", cloud.lastExport)

      LabeledContent("Synced Items") {
        Text("\(progressRows.count + subscriptionRows.count + queueRows.count)")
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private func activityRow(
    _ title: LocalizedStringKey, _ activity: CloudSyncStatus.Activity?
  ) -> some View {
    LabeledContent(title) {
      if let activity {
        if activity.isRunning {
          Text("In progress…").foregroundStyle(.secondary)
        } else if activity.succeeded {
          Text(Formatters.formatDate(activity.ended ?? activity.started, time: .shortened))
            .foregroundStyle(.secondary)
        } else if let errorDescription = activity.errorDescription {
          Text(verbatim: errorDescription)
            .foregroundStyle(.red)
            .multilineTextAlignment(.trailing)
        } else {
          Text("Failed").foregroundStyle(.red)
        }
      } else {
        Text("—").foregroundStyle(.secondary)
      }
    }
  }

  /// `Text` rather than `String`: a String handed to `Text` is shown verbatim,
  /// so these would stay English in a localized build. The one genuinely
  /// dynamic case is explicitly verbatim.
  private var accountText: Text {
    switch cloud.account {
    case .available: Text("Signed in")
    case .noAccount: Text("Not signed in")
    case .restricted: Text("Restricted")
    case .temporarilyUnavailable: Text("Temporarily unavailable")
    case .couldNotDetermine(let reason): Text(verbatim: reason)
    case .unknown: Text("Checking…")
    }
  }

  private var accountColor: Color {
    switch cloud.account {
    case .available: .green
    case .unknown: .secondary
    default: .red
    }
  }

  @ViewBuilder
  private var notificationStatusText: some View {
    switch syncManager.notificationPermissionStatus {
    case .authorized:
      Text("Enabled").font(.caption).foregroundStyle(.green)
    case .denied:
      Text("Denied — enable in system Settings").font(.caption).foregroundStyle(.red)
    case .notDetermined:
      Text("Permission required").font(.caption).foregroundStyle(.orange)
    default:
      Text("Unknown").font(.caption).foregroundStyle(.secondary)
    }
  }
}

// MARK: - Downloads

struct DownloadSettingsScreen: View {
  let viewModel: SettingsViewModel
  private var syncManager: BackgroundSyncManager { .shared }

  @AppStorage("allowCellularAutoDownload") private var allowCellularAutoDownload = false
  @AppStorage("allowAutoDownloadOnBattery") private var allowAutoDownloadOnBattery = false
  @AppStorage("episodeCacheLimit") private var episodeCacheLimit = 0
  @AppStorage("autoDeletePlayedEnabled") private var autoDeletePlayedEnabled = false

  private let cacheLimitOptions: [(label: String, value: Int)] = [
    ("Unlimited", 0),
    ("5 episodes", 5),
    ("10 episodes", 10),
    ("25 episodes", 25),
    ("50 episodes", 50)
  ]

  var body: some View {
    List {
      Section {
        Toggle(isOn: Binding(
          get: { viewModel.autoDownloadNewEpisodes },
          set: { viewModel.setAutoDownloadNewEpisodes($0) }
        )) {
          Text("Download New Episodes")
        }
        .disabled(!syncManager.isBackgroundSyncEnabled)
      } footer: {
        if syncManager.isBackgroundSyncEnabled {
          Text("New episodes from your subscriptions download automatically. Individual podcasts can override this from their ••• menu.")
        } else {
          Text("Turn on Background Sync to download new episodes automatically.")
        }
      }

      Section {
        Toggle("Use Cellular Data", isOn: $allowCellularAutoDownload)
        Toggle("Download on Battery", isOn: $allowAutoDownloadOnBattery)
      } header: {
        Text("When to Download")
      } footer: {
        Text("Off means auto-downloads wait for Wi-Fi and for a charger.")
      }

      Section {
        Picker("Keep at Most", selection: $episodeCacheLimit) {
          ForEach(cacheLimitOptions, id: \.value) { option in
            Text(option.label).tag(option.value)
          }
        }

        Toggle("Delete After Playing", isOn: $autoDeletePlayedEnabled)
      } header: {
        Text("Storage")
      } footer: {
        Text("Played episodes are removed a day after you finish them. Starred episodes are always kept.")
      }
    }
    .navigationTitle("Downloads")
    .platformToolbarTitleDisplayMode()
  }
}

// MARK: - Playback

struct PlaybackSettingsScreen: View {
  @Bindable var viewModel: SettingsViewModel

  private let playbackSpeeds: [Float] = Formatters.playbackSpeeds
  private let skipIntervalOptions: [Int] = [5, 10, 15, 20, 30, 45, 60]

  var body: some View {
    List {
      Section {
        Picker("Default Speed", selection: $viewModel.defaultPlaybackSpeed) {
          ForEach(playbackSpeeds, id: \.self) { speed in
            Text(Formatters.formatSpeed(speed)).tag(speed)
          }
        }
        .onChange(of: viewModel.defaultPlaybackSpeed) { _, newValue in
          viewModel.setDefaultPlaybackSpeed(newValue)
        }

        Toggle(isOn: Binding(
          get: { viewModel.autoPlayNextEpisode },
          set: { viewModel.setAutoPlayNextEpisode($0) }
        )) {
          Text("Play Next Automatically")
        }
      } footer: {
        Text("Playback continues from Up Next instead of stopping at the end of an episode.")
      }

      Section {
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
      } header: {
        Text("Skip Controls")
      } footer: {
        Text("Also applies to the Lock Screen and headphone controls.")
      }
    }
    .navigationTitle("Playback")
    .platformToolbarTitleDisplayMode()
  }
}

// MARK: - Transcripts

struct TranscriptSettingsScreen: View {
  @Bindable var viewModel: SettingsViewModel

  var body: some View {
    List {
      Section {
        Picker("Engine", selection: Binding(
          get: { viewModel.selectedTranscriptEngine },
          set: { viewModel.setTranscriptEngine($0) }
        )) {
          ForEach(TranscriptEngine.allCases) { engine in
            Text(engine.displayName).tag(engine)
          }
        }

        Picker("Language", selection: $viewModel.selectedTranscriptLocale) {
          ForEach(SettingsViewModel.locales(for: viewModel.selectedTranscriptEngine)) { locale in
            Text(locale.name).tag(locale.id)
          }
        }
        .onChange(of: viewModel.selectedTranscriptLocale) { _, newValue in
          viewModel.setSelectedTranscriptLocale(newValue)
        }

        if viewModel.selectedTranscriptEngine == .appleSpeech {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Speech Model")
              transcriptStatusText
            }
            Spacer()
            transcriptActionButton
          }
        }
      } footer: {
        switch viewModel.selectedTranscriptEngine {
        case .whisper:
          Text("Whisper models download once and stay on device. Larger models are more accurate and slower.")
        case .yapServer:
          Text("Yap Server is a local HTTP service wrapping Apple Speech. No model download required.")
        case .appleSpeech:
          Text("Each podcast uses the language from its RSS feed; download the model for the languages you listen to.")
        }
      }

      if viewModel.selectedTranscriptEngine == .whisper {
        WhisperModelsSection()
      }

      if viewModel.selectedTranscriptEngine == .yapServer {
        YapServerSection()
      }

      Section {
        NavigationLink {
          AutoTranscribeManagementView()
        } label: {
          Text("Automatic Transcription")
        }

        NavigationLink {
          TranscriptContextManagementView()
        } label: {
          Text("Names & Jargon")
        }
      } footer: {
        Text("Names & jargon per podcast bias recognition toward each show's vocabulary, and feed the same terms to AI analysis.")
      }

      Section {
        Toggle(isOn: Binding(
          get: { SubtitleSettingsManager.shared.enableMusicDetection },
          set: { SubtitleSettingsManager.shared.enableMusicDetection = $0 }
        )) {
          Text("Detect Music")
        }

        if SubtitleSettingsManager.shared.enableMusicDetection {
          Picker("Sensitivity", selection: Binding(
            get: { SubtitleSettingsManager.shared.musicDetectionSensitivity },
            set: { SubtitleSettingsManager.shared.musicDetectionSensitivity = $0 }
          )) {
            ForEach(MusicDetectionSensitivity.allCases, id: \.self) { level in
              Text(level.displayName).tag(level)
            }
          }
        }

        Toggle(isOn: Binding(
          get: { SubtitleSettingsManager.shared.splitLongAudio },
          set: { SubtitleSettingsManager.shared.splitLongAudio = $0 }
        )) {
          Text("Split Long Audio")
        }
      } header: {
        Text("Advanced")
      } footer: {
        Text("Music ranges are marked [♪ Music] instead of transcribed; lower sensitivity catches fainter music. Splitting transcribes in parallel parts, which is faster than a single pass.")
      }
    }
    .navigationTitle("Transcripts")
    .platformToolbarTitleDisplayMode()
  }

  @ViewBuilder
  private var transcriptStatusText: some View {
    switch viewModel.transcriptModelStatus {
    case .checking:
      Text("Checking…").font(.caption).foregroundStyle(.secondary)
    case .notDownloaded:
      Text("Not installed").font(.caption).foregroundStyle(.orange)
    case .downloading(let progress):
      Text("Downloading \(Int(progress * 100))%").font(.caption).foregroundStyle(.blue)
    case .ready:
      Text("Ready").font(.caption).foregroundStyle(.green)
    case .error(let message):
      Text(message).font(.caption).foregroundStyle(.red).lineLimit(1)
    case .simulatorNotSupported:
      Text("Requires a physical device").font(.caption).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private var transcriptActionButton: some View {
    switch viewModel.transcriptModelStatus {
    case .checking:
      ProgressView().scaleEffect(0.8)
    case .notDownloaded, .error:
      Button("Download") { viewModel.downloadTranscriptModel() }
        .buttonStyle(.accentProminent)
        .controlSize(.small)
    case .downloading(let progress):
      HStack(spacing: 8) {
        ProgressView(value: progress).frame(width: 60)
        Button {
          viewModel.cancelTranscriptDownload()
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }
    case .ready:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    case .simulatorNotSupported:
      Image(systemName: "desktopcomputer").foregroundStyle(.secondary)
    }
  }
}

// MARK: - Translation

struct TranslationSettingsScreen: View {
  var body: some View {
    List {
      Section {
        Picker("Language", selection: Binding(
          get: { SubtitleSettingsManager.shared.targetLanguage },
          set: { SubtitleSettingsManager.shared.targetLanguage = $0 }
        )) {
          ForEach(TranslationTargetLanguage.allCases, id: \.self) { language in
            Text(language.displayName).tag(language)
          }
        }

        Toggle(isOn: Binding(
          get: { SubtitleSettingsManager.shared.autoTranslateOnLoad },
          set: { SubtitleSettingsManager.shared.autoTranslateOnLoad = $0 }
        )) {
          Text("Translate Automatically")
        }
      } footer: {
        Text("Target language for transcripts and episode descriptions. Translating automatically runs as soon as a transcript loads.")
      }
    }
    .navigationTitle("Translation")
    .platformToolbarTitleDisplayMode()
  }
}

// MARK: - Subscriptions

struct SubscriptionsSettingsScreen: View {
  let viewModel: SettingsViewModel
  @Environment(\.modelContext) private var modelContext

  @State private var showAddFeedSheet = false
  @State private var showOPMLImporter = false
  @State private var showImportInstructions = false
  @State private var opmlImportMessage: String?

  var body: some View {
    List {
      Section {
        Button("Add RSS Feed") { showAddFeedSheet = true }
      }

      Section {
        Button("Import from Apple Podcasts") { showImportInstructions = true }

        Button {
          showOPMLImporter = true
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text("Import OPML File")
            if let opmlImportMessage {
              Text(opmlImportMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      } header: {
        Text("Import")
      } footer: {
        Text("Importing from Apple Podcasts uses a Shortcut. OPML import accepts a subscription export from any other podcast app.")
      }
    }
    .navigationTitle("Subscriptions")
    .platformToolbarTitleDisplayMode()
    .sheet(isPresented: $showAddFeedSheet) {
      AddFeedView(viewModel: viewModel, modelContext: modelContext) {
        showAddFeedSheet = false
      }
    }
    .sheet(isPresented: $showImportInstructions) {
      NavigationStack {
        ScrollView {
          ImportShortcutInstructionsView().padding()
        }
        .navigationTitle("Import from Apple Podcasts")
        .platformToolbarTitleDisplayMode()
        .toolbar {
          // An inline title is one line and truncates; with Done beside it
          // "Import from Apple Podcasts" became "Import from App…". A principal
          // item can shrink to fit instead of clipping.
          ToolbarItem(placement: .principal) {
            Text("Import from Apple Podcasts")
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.7)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { showImportInstructions = false }
          }
        }
      }
      .presentationDetents([.medium, .large])
    }
    .fileImporter(
      isPresented: $showOPMLImporter,
      allowedContentTypes: [.xml, UTType(filenameExtension: "opml") ?? .xml],
      allowsMultipleSelection: false
    ) { result in
      handleOPMLImport(result)
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
}

// MARK: - Appearance

struct AppearanceSettingsScreen: View {
  let viewModel: SettingsViewModel

  @AppStorage(EpisodeRowAppearanceDefaults.edgeKey)
  private var playButtonEdge = EpisodeRowPlayButtonEdge.trailing.rawValue
  @AppStorage(EpisodeRowAppearanceDefaults.sizeKey)
  private var playButtonSize = EpisodeRowPlayButtonSize.medium.rawValue

  /// Empty = System Default. Stored here rather than read through the
  /// environment because this screen is the one place that writes it.
  @AppStorage(AppAccentColorDefaults.key) private var accentRaw = ""
  @AppStorage(AppThemeDefaults.key) private var themeRaw = AppTheme.system.rawValue

  private var accentColor: Color {
    AppAccentColorDefaults.decode(accentRaw) ?? .accentColor
  }


  // MARK: - Theme

  private var themeSection: some View {
    Section {
      Picker("Appearance", selection: $themeRaw) {
        ForEach(AppTheme.allCases) { theme in
          Label(theme.titleKey, systemImage: theme.systemImage).tag(theme.rawValue)
        }
      }
      #if os(iOS)
      .pickerStyle(.segmented)
      .labelsHidden()
      #endif
    } header: {
      Text("Appearance")
    } footer: {
      Text("System follows your device's Light/Dark setting.")
    }
  }

  // MARK: - Accent

  private var accentSection: some View {
    Section {
      // Swatches first: one tap covers almost everyone, and the full picker
      // stays available underneath for anything else.
      HStack(spacing: 12) {
        ForEach(AccentPreset.allCases) { preset in
          Button {
            accentRaw = AppAccentColorDefaults.encode(preset.color)
          } label: {
            Circle()
              .fill(preset.color)
              .frame(width: 28, height: 28)
              .overlay {
                if accentRaw == AppAccentColorDefaults.encode(preset.color) {
                  Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                }
              }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(preset.titleKey)
        }
      }
      .padding(.vertical, 4)

      ColorPicker("Custom Colour", selection: Binding(
        get: { accentColor },
        set: { accentRaw = AppAccentColorDefaults.encode($0) }
      ), supportsOpacity: false)

      if !accentRaw.isEmpty {
        Button("Use System Default") { accentRaw = "" }
      }
    } header: {
      Text("Accent Colour")
    } footer: {
      Text("Tints buttons and controls throughout the app. System Default is monochrome — white on dark backgrounds, black on light.")
    }
  }

  var body: some View {
    List {
      themeSection
      accentSection

      Section {
        Toggle(isOn: Binding(
          get: { viewModel.showEpisodeArtwork },
          set: { viewModel.setShowEpisodeArtwork($0) }
        )) {
          Text("Episode Artwork")
        }
      } footer: {
        Text("Hiding artwork in episode lists reduces memory use.")
      }

      Section {
        Picker("Play Button", selection: $playButtonEdge) {
          ForEach(EpisodeRowPlayButtonEdge.allCases) { edge in
            Text(edge.titleKey).tag(edge.rawValue)
          }
        }
        #if os(iOS)
        .pickerStyle(.menu)
        #endif

        Picker("Play Button Size", selection: $playButtonSize) {
          ForEach(EpisodeRowPlayButtonSize.allCases) { size in
            Text(size.titleKey).tag(size.rawValue)
          }
        }
        #if os(iOS)
        .pickerStyle(.menu)
        #endif
      } header: {
        Text("Episode Rows")
      } footer: {
        Text("The ••• menu takes the opposite side. A larger play button is easier to hit while walking.")
      }

      Section {
        // For You needs the on-device model, so on hardware that can never run
        // it the toggle is absent rather than switchable-but-inert.
        if FoundationModelsAvailability.isSupported {
          Toggle(isOn: Binding(
            get: { viewModel.showForYouRecommendations },
            set: { viewModel.setShowForYouRecommendations($0) }
          )) {
            Text("For You")
          }
        }

        Toggle(isOn: Binding(
          get: { viewModel.showTrendingEpisodes },
          set: { viewModel.setShowTrendingEpisodes($0) }
        )) {
          Text("Trending Episodes")
        }
      } header: {
        Text("Home Screen")
      } footer: {
        if FoundationModelsAvailability.isSupported {
          Text("For You suggests episodes from your listening history. Trending shows popular episodes from top podcasts.")
        } else {
          Text("Trending shows popular episodes from top podcasts.")
        }
      }
    }
    .navigationTitle("Appearance")
    .platformToolbarTitleDisplayMode()
  }
}

// MARK: - General

struct GeneralSettingsScreen: View {
  @Bindable var viewModel: SettingsViewModel
  @State private var showingRegions = false
  @State private var regions = DiscoveryRegions.shared

  /// Flags of the ticked regions, or a count once there are too many to read
  /// at a glance in a settings row.
  private var regionSummary: String {
    let flags = regions.enabledStorefronts.map(\.flag)
    return flags.count <= 4 ? flags.joined() : "\(flags.count) regions"
  }

  var body: some View {
    List {
      Section {
        Picker("App Language", selection: Binding(
          get: { LanguageManager.shared.appLanguage },
          set: { LanguageManager.shared.appLanguage = $0 }
        )) {
          ForEach(LanguageManager.availableLanguages) { language in
            Text(language.displayName).tag(language.id)
          }
        }
        #if os(iOS)
        .pickerStyle(.menu)
        #endif

        // A flat Picker over 174 storefronts was unusable, and most people
        // want two of them — the editor handles ticking, ordering and adding
        // by code.
        Button {
          showingRegions = true
        } label: {
          HStack {
            Text("Discovery Regions")
              .foregroundStyle(.primary)
            Spacer()
            Text(regionSummary)
              .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.tertiary)
          }
        }
      } footer: {
        Text("“System Default” follows your device language. Discovery Regions decides which countries' top podcasts Home offers.")
      }

      Section {
        LabeledContent(
          "Version",
          value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        )
      }

      #if DEBUG
      Section {
        NavigationLink("Shortcuts Debug") { ShortcutsDebugView() }
      } header: {
        Text("Debug")
      } footer: {
        Text("Validate the SaveAnalysisResultIntent App Intent and observe the notification flow.")
      }
      #endif
    }
    .navigationTitle("General")
    .sheet(isPresented: $showingRegions) {
      DiscoveryRegionsView()
    }
    .platformToolbarTitleDisplayMode()
  }
}
