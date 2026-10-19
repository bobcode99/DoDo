import Foundation

// Codable, Sendable DTOs that define the on-disk shape of `backup.json`.
// Pure value types only — no SwiftData imports — so the schema is decoupled
// from the persistence layer and can be safely round-tripped on any thread.

struct BackupArchive: Codable, Sendable {
    static let currentVersion = 1

    var version: Int = BackupArchive.currentVersion
    var exportedAt: Date
    var appVersion: String
    var build: String

    var podcasts: [BackupPodcast]
    var episodes: [BackupEpisode]
    var queue: [BackupQueueItem]
    var aiAnalyses: [BackupAIAnalysis]
    var settings: BackupSettings
    var aiFormatHints: [String: String] = [:]
}

struct BackupPodcast: Codable, Sendable {
    var rssUrl: String
    var title: String
    var imageURL: String
    var language: String
    var podcastDescription: String?
    var dateAdded: Date
    var isSubscribed: Bool
    var autoTranscribeNewEpisodes: Bool
    var autoDownloadSetting: String
    var episodeFilterInclude: String
    var episodeFilterExclude: String
    var episodeFilterMinDuration: Int
    var detectedCadence: String?
}

struct BackupEpisode: Codable, Sendable {
    var podcastTitle: String
    var episodeTitle: String
    var audioURL: String
    var imageURL: String?
    var pubDate: Date?
    var duration: TimeInterval
    var lastPlaybackPosition: TimeInterval
    var isCompleted: Bool
    var lastPlayedDate: Date?
    var playCount: Int
    var isStarred: Bool
    var notes: String?
    var upNextDismissedAt: Date?
    var autoDownloadEnabled: Bool
}

struct BackupQueueItem: Codable, Sendable {
    var position: Int
    var id: String
    var episodeTitle: String
    var podcastTitle: String
    var audioURL: String
    var imageURL: String?
    var episodeDescription: String?
    var pubDate: Date?
    var duration: Int?
    var guid: String?
}

struct BackupAIAnalysis: Codable, Sendable {
    var episodeAudioURL: String
    var episodeTitle: String
    var podcastTitle: String
    var analysisJSON: String?
    var qaHistoryJSON: String?
    var provider: String?
    var model: String?
    var generatedAt: Date?
    var createdAt: Date
    var updatedAt: Date
}

struct BackupSettings: Codable, Sendable {
    var values: [String: BackupSettingValue]
}

enum BackupSettingValue: Codable, Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported BackupSettingValue payload"
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value):   try container.encode(value)
        case .int(let value):    try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }

    /// Lift an arbitrary `UserDefaults` value into a typed BackupSettingValue.
    /// Returns nil for unsupported types (arrays, dictionaries, dates, data).
    static func from(_ raw: Any) -> BackupSettingValue? {
        // CFBoolean comes back as NSNumber, but ObjC bridges it to Bool first
        // when checked against Bool — order matters here.
        if let bool = raw as? Bool, (raw as? NSNumber)?.isBool == true { return .bool(bool) }
        if let i = raw as? Int { return .int(i) }
        if let double = raw as? Double { return .double(double) }
        if let float = raw as? Float { return .double(Double(float)) }
        if let string = raw as? String { return .string(string) }
        return nil
    }

    /// Write this value back into UserDefaults under `key`.
    func write(to defaults: UserDefaults, key: String) {
        switch self {
        case .bool(let value):   defaults.set(value, forKey: key)
        case .int(let value):    defaults.set(value, forKey: key)
        case .double(let value): defaults.set(value, forKey: key)
        case .string(let value): defaults.set(value, forKey: key)
        }
    }
}

private extension NSNumber {
    /// True when this NSNumber actually wraps a CFBoolean (vs. a numeric value
    /// that happens to be 0 or 1). Used to distinguish Bool from Int in the
    /// untyped `Any` returned by `UserDefaults.object(forKey:)`.
    var isBool: Bool {
        CFGetTypeID(self) == CFBooleanGetTypeID()
    }
}

// MARK: - Settings safelist

enum BackupSettingsSafelist {
    /// Explicit list of UserDefaults keys we are willing to round-trip.
    /// Anything not on this list is excluded from backups.
    static let keys: [String] = [
        // SettingsViewModel.Keys
        "defaultPlaybackSpeed",
        "selectedTranscriptLocale",
        "selectedPodcastRegion",
        "showEpisodeArtwork",
        "autoPlayNextEpisode",
        "transcriptEngine",
        "autoDownloadNewEpisodes",
        "showTrendingEpisodes",
        "skipForwardInterval",
        "skipBackwardInterval",
        // @AppStorage in SettingsView
        "allowCellularAutoDownload",
        "allowAutoDownloadOnBattery",
        "episodeCacheLimit",
        // Language preference
        "appLanguage",
    ]

    /// Second layer of defense: any key whose name contains one of these
    /// substrings is forcibly skipped, even if it ever lands on the safelist.
    static let denySubstrings: [String] = [
        "apikey", "api_key", "token", "secret", "oauth", "password", "credential",
    ]

    static func isAllowed(_ key: String) -> Bool {
        let lower = key.lowercased()
        if denySubstrings.contains(where: { lower.contains($0) }) { return false }
        return keys.contains(key)
    }
}
