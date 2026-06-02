//
//  SubtitleSettingsModel.swift
//  PodcastAnalyzer
//
//  Settings for subtitle display and translation
//

import Foundation

// MARK: - Display Mode

/// How subtitles are displayed during playback
enum SubtitleDisplayMode: String, CaseIterable, Codable, Sendable {
  case originalOnly = "original_only"
  case translatedOnly = "translated_only"
  case dualOriginalFirst = "dual_original_first"
  case dualTranslatedFirst = "dual_translated_first"

  var displayName: String {
    switch self {
    case .originalOnly: return "Original Only"
    case .translatedOnly: return "Translated Only"
    case .dualOriginalFirst: return "Dual (Original First)"
    case .dualTranslatedFirst: return "Dual (Translated First)"
    }
  }

  var icon: String {
    switch self {
    case .originalOnly: return "text.bubble"
    case .translatedOnly: return "globe"
    case .dualOriginalFirst: return "text.bubble.fill"
    case .dualTranslatedFirst: return "globe.badge.chevron.backward"
    }
  }

  var description: String {
    switch self {
    case .originalOnly: return "Show only the original transcript"
    case .translatedOnly: return "Show only the translated text"
    case .dualOriginalFirst: return "Show original text with translation below"
    case .dualTranslatedFirst: return "Show translation with original text below"
    }
  }

  /// Whether this mode requires translation to be available
  var requiresTranslation: Bool {
    switch self {
    case .originalOnly: return false
    case .translatedOnly, .dualOriginalFirst, .dualTranslatedFirst: return true
    }
  }
}

// MARK: - Target Language

/// Available target languages for translation
enum TranslationTargetLanguage: String, CaseIterable, Codable, Sendable {
  case deviceLanguage = "device"
  case english = "en"
  case traditionalChinese = "zh-Hant"
  case simplifiedChinese = "zh-Hans"
  case japanese = "ja"
  case korean = "ko"
  case spanish = "es"
  case french = "fr"
  case german = "de"
  case portuguese = "pt"
  case italian = "it"
  case russian = "ru"
  case arabic = "ar"
  case hindi = "hi"
  case thai = "th"
  case vietnamese = "vi"

  var displayName: String {
    switch self {
    case .deviceLanguage: return "Device Language"
    case .english: return "English"
    case .traditionalChinese: return "Traditional Chinese"
    case .simplifiedChinese: return "Simplified Chinese"
    case .japanese: return "Japanese"
    case .korean: return "Korean"
    case .spanish: return "Spanish"
    case .french: return "French"
    case .german: return "German"
    case .portuguese: return "Portuguese"
    case .italian: return "Italian"
    case .russian: return "Russian"
    case .arabic: return "Arabic"
    case .hindi: return "Hindi"
    case .thai: return "Thai"
    case .vietnamese: return "Vietnamese"
    }
  }

  /// Returns the Locale.Language for Translation framework
  @available(iOS 17.4, macOS 14.4, *)
  var localeLanguage: Locale.Language? {
    switch self {
    case .deviceLanguage:
      guard let preferred = Locale.preferredLanguages.first else { return nil }
      return Locale.Language(identifier: preferred)
    default:
      return Locale.Language(identifier: rawValue)
    }
  }

  /// Short abbreviated name for compact display (e.g., badge)
  var shortName: String {
    switch self {
    case .deviceLanguage: return "Auto"
    case .english: return "EN"
    case .traditionalChinese: return "繁中"
    case .simplifiedChinese: return "简中"
    case .japanese: return "日本"
    case .korean: return "한국"
    case .spanish: return "ES"
    case .french: return "FR"
    case .german: return "DE"
    case .portuguese: return "PT"
    case .italian: return "IT"
    case .russian: return "RU"
    case .arabic: return "AR"
    case .hindi: return "HI"
    case .thai: return "TH"
    case .vietnamese: return "VI"
    }
  }

  /// Returns the language identifier string
  var languageIdentifier: String {
    switch self {
    case .deviceLanguage:
      return Locale.preferredLanguages.first ?? "en"
    default:
      return rawValue
    }
  }
}

// MARK: - Music Detection Sensitivity

/// Confidence threshold preset for the SoundAnalysis music classifier.
/// Lower thresholds catch more music (including faint background beds) but
/// risk flagging speech-with-music as music; higher thresholds only mark
/// clearly musical passages.
enum MusicDetectionSensitivity: String, CaseIterable, Codable, Sendable {
  case low
  case medium
  case high

  /// The confidence cutoff passed to `MusicDetectionService.detectMusicRanges`.
  var minimumConfidence: Double {
    switch self {
    case .low: return 0.4
    case .medium: return 0.6
    case .high: return 0.8
    }
  }

  var displayName: String {
    switch self {
    case .low: return "Low"
    case .medium: return "Medium"
    case .high: return "High"
    }
  }
}

// MARK: - Settings Manager

/// Manages subtitle display and translation preferences
@MainActor
@Observable
final class SubtitleSettingsManager {
  static let shared = SubtitleSettingsManager()

  /// How subtitles are displayed
  var displayMode: SubtitleDisplayMode = .originalOnly {
    didSet { saveSettings() }
  }

  /// Target language for translation
  var targetLanguage: TranslationTargetLanguage = .deviceLanguage {
    didSet { saveSettings() }
  }

  /// Automatically translate transcripts when loaded
  var autoTranslateOnLoad: Bool = false {
    didSet { saveSettings() }
  }

  /// Automatically download transcripts when episode is downloaded (if available in RSS)
  var autoDownloadTranscripts: Bool = true {
    didSet { saveSettings() }
  }

  /// Automatically generate transcripts for downloaded episodes
  var autoGenerateTranscripts: Bool = false {
    didSet { saveSettings() }
  }

  /// Run the SoundAnalysis music classifier during chunked Apple Speech
  /// transcription and inject `[♪ Music]` markers in place of music ranges.
  /// Default on; users with voice-over-heavy content can disable when the
  /// classifier mis-flags speech as music.
  var enableMusicDetection: Bool = true {
    didSet { saveSettings() }
  }

  /// Confidence threshold preset for the music classifier. Higher = stricter
  /// (fewer false positives on speech-with-music); lower = more aggressive
  /// (catches faint intro/outro music).
  var musicDetectionSensitivity: MusicDetectionSensitivity = .medium {
    didSet { saveSettings() }
  }

  // MARK: - UserDefaults Keys

  private enum Keys {
    static let displayMode = "subtitle_display_mode"
    static let targetLanguage = "subtitle_target_language"
    static let autoTranslate = "subtitle_auto_translate"
    static let autoDownloadTranscripts = "subtitle_auto_download_transcripts"
    static let autoGenerateTranscripts = "subtitle_auto_generate_transcripts"
    static let enableMusicDetection = "subtitle_enable_music_detection"
    static let musicDetectionSensitivity = "subtitle_music_detection_sensitivity"
  }

  // MARK: - Initialization

  private init() {
    loadSettings()
  }

  // MARK: - Persistence

  private func loadSettings() {
    let defaults = UserDefaults.standard

    if let modeString = defaults.string(forKey: Keys.displayMode),
       let mode = SubtitleDisplayMode(rawValue: modeString) {
      displayMode = mode
    }

    if let langString = defaults.string(forKey: Keys.targetLanguage),
       let lang = TranslationTargetLanguage(rawValue: langString) {
      targetLanguage = lang
    }

    autoTranslateOnLoad = defaults.bool(forKey: Keys.autoTranslate)

    // Default to true for auto-download if not set
    if defaults.object(forKey: Keys.autoDownloadTranscripts) == nil {
      autoDownloadTranscripts = true
    } else {
      autoDownloadTranscripts = defaults.bool(forKey: Keys.autoDownloadTranscripts)
    }

    if defaults.object(forKey: Keys.autoGenerateTranscripts) != nil {
      autoGenerateTranscripts = defaults.bool(forKey: Keys.autoGenerateTranscripts)
    }

    // Default to true if not previously set.
    if defaults.object(forKey: Keys.enableMusicDetection) != nil {
      enableMusicDetection = defaults.bool(forKey: Keys.enableMusicDetection)
    }

    if let raw = defaults.string(forKey: Keys.musicDetectionSensitivity),
       let value = MusicDetectionSensitivity(rawValue: raw) {
      musicDetectionSensitivity = value
    }
  }

  private func saveSettings() {
    let defaults = UserDefaults.standard
    defaults.set(displayMode.rawValue, forKey: Keys.displayMode)
    defaults.set(targetLanguage.rawValue, forKey: Keys.targetLanguage)
    defaults.set(autoTranslateOnLoad, forKey: Keys.autoTranslate)
    defaults.set(autoDownloadTranscripts, forKey: Keys.autoDownloadTranscripts)
    defaults.set(autoGenerateTranscripts, forKey: Keys.autoGenerateTranscripts)
    defaults.set(enableMusicDetection, forKey: Keys.enableMusicDetection)
    defaults.set(musicDetectionSensitivity.rawValue, forKey: Keys.musicDetectionSensitivity)
  }

  // MARK: - Translation Availability

  /// Check if Translation framework is available on this device
  nonisolated var isTranslationAvailable: Bool {
    if #available(iOS 17.4, macOS 14.4, *) {
      return true
    }
    return false
  }

  /// Whether dual subtitle mode is enabled
  var isDualMode: Bool {
    displayMode == .dualOriginalFirst || displayMode == .dualTranslatedFirst
  }

  /// Whether translation is needed for current display mode
  var needsTranslation: Bool {
    displayMode.requiresTranslation
  }
}
