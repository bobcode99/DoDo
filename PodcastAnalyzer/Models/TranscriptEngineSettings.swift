//
//  TranscriptEngineSettings.swift
//  PodcastAnalyzer
//
//  Models and manager for transcript engine selection (Apple Speech vs Whisper).
//

import Foundation
import OSLog

// MARK: - TranscriptEngine

/// Which engine to use for on-device transcription.
enum TranscriptEngine: String, CaseIterable, Identifiable {
    case appleSpeech = "apple_speech"
    case whisper = "whisper"
    case yapServer = "yap_server"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech: "Apple Speech"
        case .whisper: "Whisper (OpenAI)"
        case .yapServer: "Yap Server"
        }
    }

    var description: String {
        switch self {
        case .appleSpeech:
            "Built-in on-device speech recognition. Fast setup, no extra download required."
        case .whisper:
            "OpenAI Whisper via WhisperKit. Higher accuracy, especially for technical content and accents. Requires model download."
        case .yapServer:
            "Remote Apple Speech transcription via a local yap HTTP server. No model download required."
        }
    }

    var systemImage: String {
        switch self {
        case .appleSpeech: "waveform"
        case .whisper: "cpu"
        case .yapServer: "server.rack"
        }
    }
}

// MARK: - WhisperModelVariant

/// Available Whisper model sizes with their tradeoffs.
enum WhisperModelVariant: String, CaseIterable, Identifiable {
    case tiny = "openai_whisper-tiny"
    case base = "openai_whisper-base"
    case small = "openai_whisper-small"
    case medium = "openai_whisper-medium"
    case largeV3Turbo = "openai_whisper-large-v3-turbo"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: "Tiny"
        case .base: "Base"
        case .small: "Small"
        case .medium: "Medium"
        case .largeV3Turbo: "Large v3 Turbo"
        }
    }

    var approximateSize: String {
        switch self {
        case .tiny: "~75 MB"
        case .base: "~142 MB"
        case .small: "~466 MB"
        case .medium: "~1.5 GB"
        case .largeV3Turbo: "~1.6 GB"
        }
    }

    var approximateSizeBytes: Int64 {
        switch self {
        case .tiny: 75_000_000
        case .base: 142_000_000
        case .small: 466_000_000
        case .medium: 1_500_000_000
        case .largeV3Turbo: 1_600_000_000
        }
    }

    var accuracyNote: String {
        switch self {
        case .tiny: "Fastest, lowest accuracy"
        case .base: "Good balance for older devices"
        case .small: "Recommended — best accuracy/speed ratio"
        case .medium: "High accuracy, macOS recommended"
        case .largeV3Turbo: "Highest accuracy, Apple Silicon recommended"
        }
    }

    /// Which platform/device this model best suits.
    var recommendedFor: String {
        switch self {
        case .tiny: "iPhone 11 and older / iPod Touch"
        case .base: "iPhone 12–13 / older Macs"
        case .small: "iPhone 14+ / iPad / any Mac"
        case .medium: "macOS (Apple Silicon recommended)"
        case .largeV3Turbo: "macOS Apple Silicon (M1+)"
        }
    }

    /// Whether this variant is suitable for the current platform.
    var isSuitableForCurrentPlatform: Bool {
        #if os(macOS)
        return true  // All models usable on macOS; large ones may be slow on Intel
        #else
        // On iOS, medium and large are impractical for most devices
        switch self {
        case .tiny, .base, .small: return true
        case .medium, .largeV3Turbo: return false
        }
        #endif
    }

    /// Default recommended model per platform.
    static var platformDefault: WhisperModelVariant {
        #if os(macOS)
        return .medium
        #else
        return .small
        #endif
    }
}

// MARK: - WhisperModelStatus

enum WhisperModelStatus: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case ready
    case error(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}

// MARK: - WhisperModelManager

/// Manages WhisperKit model download, storage, and selection across the app.
@MainActor
@Observable
final class WhisperModelManager {
    static let shared = WhisperModelManager()

    var selectedModel: WhisperModelVariant = .platformDefault
    /// Per-variant download/readiness status.
    var modelStatuses: [WhisperModelVariant: WhisperModelStatus] = {
        var dict: [WhisperModelVariant: WhisperModelStatus] = [:]
        for v in WhisperModelVariant.allCases { dict[v] = .notDownloaded }
        return dict
    }()

    private var downloadTasks: [WhisperModelVariant: Task<Void, Never>] = [:]
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "WhisperModelManager")

    private enum Keys {
        static let selectedModel = "whisper_selected_model"
    }

    private init() {
        loadSelectedModel()
    }

    // MARK: - Persistence

    private func loadSelectedModel() {
        if let raw = UserDefaults.standard.string(forKey: Keys.selectedModel),
           let variant = WhisperModelVariant(rawValue: raw) {
            selectedModel = variant
        } else {
            selectedModel = .platformDefault
        }
    }

    func setSelectedModel(_ variant: WhisperModelVariant) {
        selectedModel = variant
        UserDefaults.standard.set(variant.rawValue, forKey: Keys.selectedModel)
        logger.info("Whisper selected model set to \(variant.rawValue)")
    }

    // MARK: - Model Status

    /// Checks which models are already downloaded on disk and updates statuses.
    func checkAllModelStatuses() {
        for variant in WhisperModelVariant.allCases {
            let exists = WhisperModelManager.modelExistsOnDisk(variant)
            modelStatuses[variant] = exists ? .ready : .notDownloaded
        }
    }

    func status(for variant: WhisperModelVariant) -> WhisperModelStatus {
        modelStatuses[variant] ?? .notDownloaded
    }

    // MARK: - Download

    func downloadModel(_ variant: WhisperModelVariant) {
        guard !(modelStatuses[variant]?.isDownloading ?? false) else { return }
        guard modelStatuses[variant] != .ready else { return }

        downloadTasks[variant]?.cancel()
        modelStatuses[variant] = .downloading(progress: 0)

        downloadTasks[variant] = Task { [weak self] in
            guard let self else { return }
            do {
                try await WhisperTranscriptService.downloadModel(
                    variant: variant,
                    onProgress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.modelStatuses[variant] = .downloading(progress: progress)
                        }
                    }
                )
                modelStatuses[variant] = .ready
                logger.info("Whisper model downloaded: \(variant.rawValue)")
            } catch is CancellationError {
                modelStatuses[variant] = .notDownloaded
            } catch {
                modelStatuses[variant] = .error(error.localizedDescription)
                logger.error("Whisper model download failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelDownload(_ variant: WhisperModelVariant) {
        downloadTasks[variant]?.cancel()
        downloadTasks[variant] = nil
        if modelStatuses[variant]?.isDownloading ?? false {
            modelStatuses[variant] = .notDownloaded
        }
        logger.info("Cancelled Whisper model download: \(variant.rawValue)")
    }

    func deleteModel(_ variant: WhisperModelVariant) {
        WhisperModelManager.deleteModelFromDisk(variant)
        modelStatuses[variant] = .notDownloaded
        logger.info("Deleted Whisper model: \(variant.rawValue)")
    }

    // MARK: - Disk Helpers

    /// WhisperKit's HubApi stores models in `~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/`.
    private static func modelDirectory(for variant: WhisperModelVariant) -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(variant.rawValue)
    }

    static func modelExistsOnDisk(_ variant: WhisperModelVariant) -> Bool {
        FileManager.default.fileExists(atPath: modelDirectory(for: variant).path)
    }

    static func deleteModelFromDisk(_ variant: WhisperModelVariant) {
        try? FileManager.default.removeItem(at: modelDirectory(for: variant))
    }

    static func modelSizeOnDisk(_ variant: WhisperModelVariant) -> Int64 {
        let modelDir = modelDirectory(for: variant)
        guard let enumerator = FileManager.default.enumerator(
            at: modelDir,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}

// MARK: - YapServerSettings

/// Persists connection settings for the local yap transcription server.
@MainActor
@Observable
final class YapServerSettings {
    static let shared = YapServerSettings()

    var serverURL: String = "http://127.0.0.1:8080"
    var apiKey: String = ""

    private enum Keys {
        static let serverURL = "yap_server_url"
        static let apiKey = "yap_server_api_key"
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Keys.serverURL), !saved.isEmpty {
            serverURL = saved
        }
        apiKey = UserDefaults.standard.string(forKey: Keys.apiKey) ?? ""
    }

    func save() {
        UserDefaults.standard.set(serverURL, forKey: Keys.serverURL)
        UserDefaults.standard.set(apiKey, forKey: Keys.apiKey)
    }

}
