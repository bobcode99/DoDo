import SwiftUI
import Foundation
import SwiftData
import OSLog

// MARK: - Transcript Model Status
enum TranscriptModelStatus: Equatable {
  case checking
  case notDownloaded
  case downloading(progress: Double)
  case ready
  case error(String)
  case simulatorNotSupported

  var isReady: Bool {
    if case .ready = self { return true }
    return false
  }

  var isDownloading: Bool {
    if case .downloading = self { return true }
    return false
  }

  static var isSimulator: Bool {
    #if targetEnvironment(simulator)
      return true
    #else
      return false
    #endif
  }
}

@MainActor
@Observable
final class SettingsViewModel {
  var rssUrlInput: String = ""
  var successMessage: String = ""
  var errorMessage: String = ""
  var podcastInfoModelList: [PodcastInfoModel] = []
  var isValidating: Bool = false
  var defaultPlaybackSpeed: Float = 1.0

  // Transcript model status and locale
  var transcriptModelStatus: TranscriptModelStatus = .checking
  var selectedTranscriptLocale: String = "zh-tw"

  private var successMessageTask: Task<Void, Never>?
  private var transcriptDownloadTask: Task<Void, Never>?
  private var transcriptModelStatusTask: Task<Void, Never>?
  private let service = PodcastRssService()
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "SettingsViewModel")

  // Default region for top podcasts
  var selectedRegion: String = "us"

  // Appearance settings
  var showEpisodeArtwork: Bool = true

  // Playback settings
  var autoPlayNextEpisode: Bool = false

  // For You recommendations
  var showForYouRecommendations: Bool = true

  // Auto-download
  var autoDownloadNewEpisodes: Bool = false

  // Trending episodes
  var showTrendingEpisodes: Bool = true

  // Skip intervals
  var skipForwardInterval: Int = 30
  var skipBackwardInterval: Int = 15

  private enum Keys {
    static let defaultPlaybackSpeed = "defaultPlaybackSpeed"
    static let selectedTranscriptLocale = "selectedTranscriptLocale"
    static let selectedPodcastRegion = "selectedPodcastRegion"
    static let showEpisodeArtwork = "showEpisodeArtwork"
    static let autoPlayNextEpisode = "autoPlayNextEpisode"
    static let showForYouRecommendations = "showForYouRecommendations"
    static let transcriptEngine = "transcriptEngine"
    static let autoDownloadNewEpisodes = "autoDownloadNewEpisodes"
    static let showTrendingEpisodes = "showTrendingEpisodes"
    static let skipForwardInterval = "skipForwardInterval"
    static let skipBackwardInterval = "skipBackwardInterval"
  }

  // MARK: - Transcript Engine

  var selectedTranscriptEngine: TranscriptEngine = .appleSpeech

  func setTranscriptEngine(_ engine: TranscriptEngine) {
    selectedTranscriptEngine = engine
    UserDefaults.standard.set(engine.rawValue, forKey: Keys.transcriptEngine)
    logger.info("Transcript engine set to \(engine.rawValue)")
    // Refresh Apple Speech model status whenever switching back
    switch engine {
    case .appleSpeech:
      checkTranscriptModelStatus()
    case .whisper:
      WhisperModelManager.shared.checkAllModelStatuses()
    case .yapServer:
      logger.info("Yap Server engine selected — no model download required")
    }
  }

  private func loadTranscriptEngine() {
    if let raw = UserDefaults.standard.string(forKey: Keys.transcriptEngine),
       let engine = TranscriptEngine(rawValue: raw) {
      selectedTranscriptEngine = engine
    } else {
      selectedTranscriptEngine = .appleSpeech
    }
  }

  init() {
    loadDefaultPlaybackSpeed()
    loadSelectedTranscriptLocale()
    loadSelectedRegion()
    loadShowEpisodeArtwork()
    loadAutoPlayNextEpisode()
    loadShowForYouRecommendations()
    loadTranscriptEngine()
    loadAutoDownloadNewEpisodes()
    loadShowTrendingEpisodes()
    loadSkipIntervals()
  }

  // Tasks are cancelled via cleanup() from onDisappear; deinit removed
  // because accessing @MainActor properties from nonisolated deinit is invalid.

  // MARK: - Region Settings

  func setSelectedRegion(_ region: String) {
    selectedRegion = region
    UserDefaults.standard.set(region, forKey: Keys.selectedPodcastRegion)
    logger.info("Selected region set to \(region)")
    // Post notification so HomeViewModel can update
    NotificationCenter.default.post(name: .podcastRegionChanged, object: region)
  }

  private func loadSelectedRegion() {
    if let saved = UserDefaults.standard.string(forKey: Keys.selectedPodcastRegion) {
      selectedRegion = saved
    } else {
      selectedRegion = "us"
    }
  }

  // MARK: - Appearance Settings

  func setShowEpisodeArtwork(_ show: Bool) {
    showEpisodeArtwork = show
    UserDefaults.standard.set(show, forKey: Keys.showEpisodeArtwork)
    logger.info("Show episode artwork set to \(show)")
  }

  private func loadShowEpisodeArtwork() {
    // Default to true if not set
    if UserDefaults.standard.object(forKey: Keys.showEpisodeArtwork) == nil {
      showEpisodeArtwork = true
    } else {
      showEpisodeArtwork = UserDefaults.standard.bool(forKey: Keys.showEpisodeArtwork)
    }
  }

  // MARK: - Playback Settings

  func setAutoPlayNextEpisode(_ enabled: Bool) {
    autoPlayNextEpisode = enabled
    UserDefaults.standard.set(enabled, forKey: Keys.autoPlayNextEpisode)
    logger.info("Auto-play next episode set to \(enabled)")
  }

  private func loadAutoPlayNextEpisode() {
    // Default to false if not set
    autoPlayNextEpisode = UserDefaults.standard.bool(forKey: Keys.autoPlayNextEpisode)
  }

  // MARK: - For You Recommendations Settings

  func setShowForYouRecommendations(_ show: Bool) {
    showForYouRecommendations = show
    UserDefaults.standard.set(show, forKey: Keys.showForYouRecommendations)
    logger.info("Show For You recommendations set to \(show)")
  }

  private func loadShowForYouRecommendations() {
    // Default to true if not set
    if UserDefaults.standard.object(forKey: Keys.showForYouRecommendations) == nil {
      showForYouRecommendations = true
    } else {
      showForYouRecommendations = UserDefaults.standard.bool(forKey: Keys.showForYouRecommendations)
    }
  }

  // MARK: - Auto-Download Settings

  func setAutoDownloadNewEpisodes(_ enabled: Bool) {
    autoDownloadNewEpisodes = enabled
    UserDefaults.standard.set(enabled, forKey: Keys.autoDownloadNewEpisodes)
    logger.info("Auto-download new episodes set to \(enabled)")
  }

  private func loadAutoDownloadNewEpisodes() {
    autoDownloadNewEpisodes = UserDefaults.standard.bool(forKey: Keys.autoDownloadNewEpisodes)
  }

  // MARK: - Trending Episodes Settings

  func setShowTrendingEpisodes(_ show: Bool) {
    showTrendingEpisodes = show
    UserDefaults.standard.set(show, forKey: Keys.showTrendingEpisodes)
    logger.info("Show trending episodes set to \(show)")
  }

  private func loadShowTrendingEpisodes() {
    if UserDefaults.standard.object(forKey: Keys.showTrendingEpisodes) == nil {
      showTrendingEpisodes = true
    } else {
      showTrendingEpisodes = UserDefaults.standard.bool(forKey: Keys.showTrendingEpisodes)
    }
  }

  // MARK: - Transcript Locale Settings

  struct TranscriptLocaleOption: Identifiable, Hashable {
    let id: String  // locale code like "zh-tw"
    let name: String  // display name like "繁體中文 (台灣)"
  }

  /// Locales supported by Apple Speech (iOS 17+ on-device).
  /// This is a subset — Apple Speech requires exact locale matches and model downloads.
  static let appleSpeechLocales: [TranscriptLocaleOption] = [
    TranscriptLocaleOption(id: "zh-tw", name: "繁體中文 (台灣)"),
    TranscriptLocaleOption(id: "zh-cn", name: "简体中文 (中国)"),
    TranscriptLocaleOption(id: "en-us", name: "English (US)"),
    TranscriptLocaleOption(id: "en-gb", name: "English (UK)"),
    TranscriptLocaleOption(id: "ja-jp", name: "日本語"),
    TranscriptLocaleOption(id: "ko-kr", name: "한국어"),
    TranscriptLocaleOption(id: "fr-fr", name: "Français"),
    TranscriptLocaleOption(id: "de-de", name: "Deutsch"),
    TranscriptLocaleOption(id: "es-es", name: "Español"),
    TranscriptLocaleOption(id: "it-it", name: "Italiano"),
    TranscriptLocaleOption(id: "pt-br", name: "Português (Brasil)"),
    TranscriptLocaleOption(id: "ru", name: "Русский"),
    TranscriptLocaleOption(id: "ar", name: "العربية"),
    TranscriptLocaleOption(id: "hi", name: "हिन्दी"),
    TranscriptLocaleOption(id: "th", name: "ไทย"),
    TranscriptLocaleOption(id: "tr", name: "Türkçe"),
  ]

  /// Returns locales appropriate for the given engine
  static func locales(for engine: TranscriptEngine) -> [TranscriptLocaleOption] {
    switch engine {
    case .appleSpeech: return appleSpeechLocales
    case .whisper: return availableTranscriptLocales
    case .yapServer: return appleSpeechLocales
    }
  }

  /// All locales for Whisper (supports 50+ languages)

  static let availableTranscriptLocales: [TranscriptLocaleOption] = [
    TranscriptLocaleOption(id: "auto", name: "Auto-detect"),
    // East Asian
    TranscriptLocaleOption(id: "zh-tw", name: "繁體中文 (台灣)"),
    TranscriptLocaleOption(id: "zh-cn", name: "简体中文 (中国)"),
    TranscriptLocaleOption(id: "ja-jp", name: "日本語"),
    TranscriptLocaleOption(id: "ko-kr", name: "한국어"),
    // English
    TranscriptLocaleOption(id: "en-us", name: "English (US)"),
    TranscriptLocaleOption(id: "en-gb", name: "English (UK)"),
    // Southeast Asian
    TranscriptLocaleOption(id: "ms", name: "Bahasa Melayu"),
    TranscriptLocaleOption(id: "id", name: "Bahasa Indonesia"),
    TranscriptLocaleOption(id: "th", name: "ไทย"),
    TranscriptLocaleOption(id: "vi", name: "Tiếng Việt"),
    TranscriptLocaleOption(id: "tl", name: "Filipino"),
    // South Asian
    TranscriptLocaleOption(id: "hi", name: "हिन्दी"),
    TranscriptLocaleOption(id: "ta", name: "தமிழ்"),
    TranscriptLocaleOption(id: "bn", name: "বাংলা"),
    TranscriptLocaleOption(id: "ur", name: "اردو"),
    // Middle East
    TranscriptLocaleOption(id: "ar", name: "العربية"),
    TranscriptLocaleOption(id: "he", name: "עברית"),
    TranscriptLocaleOption(id: "fa", name: "فارسی"),
    TranscriptLocaleOption(id: "tr", name: "Türkçe"),
    // Western European
    TranscriptLocaleOption(id: "fr-fr", name: "Français"),
    TranscriptLocaleOption(id: "de-de", name: "Deutsch"),
    TranscriptLocaleOption(id: "es-es", name: "Español"),
    TranscriptLocaleOption(id: "it-it", name: "Italiano"),
    TranscriptLocaleOption(id: "pt-br", name: "Português (Brasil)"),
    TranscriptLocaleOption(id: "pt-pt", name: "Português (Portugal)"),
    TranscriptLocaleOption(id: "nl", name: "Nederlands"),
    TranscriptLocaleOption(id: "ca", name: "Català"),
    // Northern European
    TranscriptLocaleOption(id: "sv", name: "Svenska"),
    TranscriptLocaleOption(id: "no", name: "Norsk"),
    TranscriptLocaleOption(id: "da", name: "Dansk"),
    TranscriptLocaleOption(id: "fi", name: "Suomi"),
    // Eastern European
    TranscriptLocaleOption(id: "pl", name: "Polski"),
    TranscriptLocaleOption(id: "ru", name: "Русский"),
    TranscriptLocaleOption(id: "uk", name: "Українська"),
    TranscriptLocaleOption(id: "cs", name: "Čeština"),
    TranscriptLocaleOption(id: "sk", name: "Slovenčina"),
    TranscriptLocaleOption(id: "ro", name: "Română"),
    TranscriptLocaleOption(id: "hu", name: "Magyar"),
    TranscriptLocaleOption(id: "hr", name: "Hrvatski"),
    TranscriptLocaleOption(id: "bg", name: "Български"),
    TranscriptLocaleOption(id: "sr", name: "Srpski"),
    TranscriptLocaleOption(id: "el", name: "Ελληνικά"),
    // Other
    TranscriptLocaleOption(id: "af", name: "Afrikaans"),
    TranscriptLocaleOption(id: "sw", name: "Kiswahili"),
  ]

  func setSelectedTranscriptLocale(_ locale: String) {
    selectedTranscriptLocale = locale
    UserDefaults.standard.set(locale, forKey: Keys.selectedTranscriptLocale)
    logger.info("Selected transcript locale set to \(locale)")
    // Re-check model status for new locale
    checkTranscriptModelStatus()
  }

  private func loadSelectedTranscriptLocale() {
    if let saved = UserDefaults.standard.string(forKey: Keys.selectedTranscriptLocale) {
      selectedTranscriptLocale = saved
    } else {
      // Default to zh-tw
      selectedTranscriptLocale = "zh-tw"
    }
  }

  // MARK: - Public Methods

  func addRssLink(modelContext: ModelContext, onSuccess: (() -> Void)? = nil) {
    let trimmedLink = rssUrlInput.trimmingCharacters(in: .whitespaces)

    // Validate URL format
    guard isValidURL(trimmedLink) else {
      errorMessage = "Please enter a valid URL"
      successMessage = ""
      return
    }

    // Check for duplicates
    guard !podcastInfoModelList.contains(where: { $0.podcastInfo.rssUrl == trimmedLink }) else {
      errorMessage = "This feed is already added"
      successMessage = ""
      return
    }

    // Start validation
    isValidating = true
    errorMessage = ""
    successMessage = ""

    // Fetch and validate RSS feed
    Task { [weak self] in
      guard let self else { return }

      do {
        logger.info("Validating RSS feed: \(trimmedLink)")

        // Fetch happens on background thread
        let podcastInfo = try await service.fetchPodcast(from: trimmedLink)
        logger.info("RSS feed is valid: \(podcastInfo.title)")
        logger.debug("image url: \(podcastInfo.imageURL)")

        // Create new podcast feed
        let podcastInfoModel = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date.now)

        // Save to database
        modelContext.insert(podcastInfoModel)
        do {
          try modelContext.save()
        } catch {
          modelContext.delete(podcastInfoModel)
          throw error
        }

        podcastInfoModelList.append(podcastInfoModel)
        rssUrlInput = ""
        errorMessage = ""
        successMessage = "Feed added successfully!"
        logger.info("Feed saved to database: \(podcastInfo.title)")

        isValidating = false

        // Call success callback
        onSuccess?()

        // Hide success message after 2 seconds
        successMessageTask?.cancel()
        successMessageTask = Task { @MainActor in
          try? await Task.sleep(nanoseconds: 2_000_000_000)
          if !Task.isCancelled {
            self.successMessage = ""
          }
        }
      } catch let error as PodcastServiceError {
        logger.error("RSS validation failed: \(error.localizedDescription)")
        errorMessage = "Invalid RSS feed: \(error.localizedDescription)"
        successMessage = ""
        isValidating = false
      } catch {
        logger.error("Unexpected error: \(error.localizedDescription)")
        errorMessage = "Error: \(error.localizedDescription)"
        successMessage = ""
        isValidating = false
      }
    }
  }

  func removePodcastFeed(_ podcastInfoModel: PodcastInfoModel, modelContext: ModelContext) {
    do {
      modelContext.delete(podcastInfoModel)
      try modelContext.save()
      podcastInfoModelList.removeAll { $0.id == podcastInfoModel.id }
      errorMessage = ""
      self.logger.info("Feed deleted: \(podcastInfoModel.podcastInfo.title)")
    } catch {
      errorMessage = "Failed to delete feed: \(error.localizedDescription)"
      self.logger.error("Failed to delete feed: \(error.localizedDescription)")
    }
  }

  func loadFeeds(modelContext: ModelContext) {
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
    )

    do {
      podcastInfoModelList = try modelContext.fetch(descriptor)
      errorMessage = ""
      self.logger.info("Loaded \(self.podcastInfoModelList.count) feeds")
    } catch {
      errorMessage = "Failed to load feeds: \(error.localizedDescription)"
      self.logger.error("Failed to load feeds: \(error.localizedDescription)")
    }
  }

  func clearMessages() {
    successMessage = ""
    errorMessage = ""
    rssUrlInput = ""
  }

  // MARK: - Playback Speed Settings

  func setDefaultPlaybackSpeed(_ speed: Float) {
    defaultPlaybackSpeed = speed
    UserDefaults.standard.set(speed, forKey: Keys.defaultPlaybackSpeed)
    logger.info("Default playback speed set to \(speed)x")
  }

  private func loadDefaultPlaybackSpeed() {
    let savedSpeed = UserDefaults.standard.float(forKey: Keys.defaultPlaybackSpeed)
    defaultPlaybackSpeed = savedSpeed > 0 ? savedSpeed : 1.0
  }

  // MARK: - Skip Interval Settings

  func setSkipForwardInterval(_ seconds: Int) {
    skipForwardInterval = seconds
    UserDefaults.standard.set(seconds, forKey: Keys.skipForwardInterval)
  }

  func setSkipBackwardInterval(_ seconds: Int) {
    skipBackwardInterval = seconds
    UserDefaults.standard.set(seconds, forKey: Keys.skipBackwardInterval)
  }

  private func loadSkipIntervals() {
    let fwd = UserDefaults.standard.integer(forKey: Keys.skipForwardInterval)
    skipForwardInterval = fwd > 0 ? fwd : 30
    let bwd = UserDefaults.standard.integer(forKey: Keys.skipBackwardInterval)
    skipBackwardInterval = bwd > 0 ? bwd : 15
  }

  // MARK: - Transcript Model Management

  func checkTranscriptModelStatus() {
    // Check if running on simulator
    #if targetEnvironment(simulator)
      transcriptModelStatus = .simulatorNotSupported
      logger.info("Transcript model download not supported on simulator")
      return
    #else
      transcriptModelStatus = .checking

      transcriptModelStatusTask?.cancel()
      transcriptModelStatusTask = Task {
        let transcriptService = TranscriptService(language: selectedTranscriptLocale)
        let isReady = await transcriptService.isModelReady()

        if isReady {
          transcriptModelStatus = .ready
        } else {
          transcriptModelStatus = .notDownloaded
          logger.info("Transcript model not downloaded")
        }
      }
    #endif
  }

  func downloadTranscriptModel() {
    guard !transcriptModelStatus.isDownloading else { return }

    transcriptDownloadTask?.cancel()
    transcriptModelStatus = .downloading(progress: 0)

    transcriptDownloadTask = Task { [weak self] in
      guard let self else { return }

      let transcriptService = TranscriptService(language: selectedTranscriptLocale)

      for await progress in await transcriptService.setupAndInstallAssets() {
        if Task.isCancelled { break }
        transcriptModelStatus = .downloading(progress: progress)
      }

      if !Task.isCancelled {
        // Verify installation
        let isReady = await transcriptService.isModelReady()

        if isReady {
          transcriptModelStatus = .ready
          logger.info("Transcript model downloaded successfully")
        } else {
          transcriptModelStatus = .error("Download completed but model not ready")
          logger.error("Transcript model download failed verification")
        }
      }
    }
  }

  func cancelTranscriptDownload() {
    transcriptDownloadTask?.cancel()
    transcriptDownloadTask = nil
    transcriptModelStatus = .notDownloaded
    logger.info("Transcript model download cancelled")
  }

  // MARK: - Private Methods

  private func isValidURL(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString) else { return false }
    return url.scheme != nil && url.host != nil
  }
}
