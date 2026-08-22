import Foundation
import Observation
import SwiftData
import OSLog

@Observable
@MainActor
final class BackupService {
    static let shared = BackupService()

    var isExporting = false
    var isImporting = false
    var progress: Double = 0
    var status: String = ""
    var lastError: String?
    var lastSummary: ImportSummary?
    var showProgressSheet = false

    @ObservationIgnored
    private var modelContext: ModelContext?

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "Backup")

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Export

    enum BackupError: LocalizedError {
        case noContext
        case unsupportedVersion(Int)
        case readFailed
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .noContext: "Backup service is not connected to the database."
            case .unsupportedVersion(let v): "This backup was made by a newer app version (v\(v))."
            case .readFailed: "Could not read the selected file."
            case .decodeFailed: "The selected file is not a valid PodcastAnalyzer backup."
            }
        }
    }

    func exportBackup() async throws -> URL {
        guard let ctx = modelContext else { throw BackupError.noContext }

        isExporting = true
        progress = 0
        status = "Gathering library…"
        defer { isExporting = false }

        let podcastModels = (try? ctx.fetch(FetchDescriptor<PodcastInfoModel>())) ?? []
        let episodeModels = (try? ctx.fetch(FetchDescriptor<EpisodeDownloadModel>())) ?? []
        let queueModels = (try? ctx.fetch(
            FetchDescriptor<QueueItemModel>(sortBy: [SortDescriptor(\.position)])
        )) ?? []
        let analysisModels = (try? ctx.fetch(FetchDescriptor<EpisodeAIAnalysis>())) ?? []

        progress = 0.5
        status = "Encoding…"

        let archive = BackupArchive(
            version: BackupArchive.currentVersion,
            exportedAt: Date(),
            appVersion: Bundle.main.shortVersion,
            build: Bundle.main.buildNumber,
            podcasts: podcastModels.map(BackupPodcast.init(from:)),
            episodes: episodeModels.map(BackupEpisode.init(from:)),
            queue: queueModels.map(BackupQueueItem.init(from:)),
            aiAnalyses: analysisModels.map(BackupAIAnalysis.init(from:)),
            settings: BackupSettings.snapshotSafe(),
            aiFormatHints: AISettingsManager.shared.allFormatHints
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("podcast-backup-\(stamp).json")
        try data.write(to: url, options: .atomic)

        progress = 1
        status = "Export ready"
        logger.info("Wrote backup with \(archive.podcasts.count) podcasts, \(archive.episodes.count) episodes, \(archive.queue.count) queue items.")
        return url
    }

    // MARK: - Import

    struct ImportSummary: Sendable {
        var podcastsAdded: Int = 0
        var podcastsMerged: Int = 0
        var podcastsFailed: Int = 0
        var episodesInserted: Int = 0
        var episodesUpdated: Int = 0
        var queueReplaced: Int = 0
        var analysesUpserted: Int = 0
        var settingsApplied: Int = 0
        var formatHintsRestored: Int = 0
        var warnings: [String] = []
    }

    func importBackup(from url: URL) async {
        guard let ctx = modelContext else {
            lastError = BackupError.noContext.errorDescription
            return
        }

        isImporting = true
        showProgressSheet = true
        progress = 0
        status = "Reading file…"
        lastError = nil
        lastSummary = nil
        defer { isImporting = false }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let archive: BackupArchive
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            archive = try decoder.decode(BackupArchive.self, from: data)
        } catch {
            logger.error("Backup decode failed: \(error.localizedDescription, privacy: .public)")
            lastError = BackupError.decodeFailed.errorDescription
            return
        }

        guard archive.version <= BackupArchive.currentVersion else {
            lastError = BackupError.unsupportedVersion(archive.version).errorDescription
            return
        }

        var summary = ImportSummary()

        // 1. Subscriptions — reuse PodcastImportManager (de-dupes by rssUrl/title,
        //    fetches RSS only when the podcast is unknown).
        let subscribedPodcasts = archive.podcasts.filter(\.isSubscribed)
        let rssURLs = subscribedPodcasts.map(\.rssUrl)
        if !rssURLs.isEmpty {
            status = "Importing podcasts…"
            progress = 0.05
            PodcastImportManager.shared.setModelContext(ctx)
            await PodcastImportManager.shared.importPodcasts(from: rssURLs)
            if let r = PodcastImportManager.shared.importResults {
                summary.podcastsAdded = r.successful
                summary.podcastsMerged = r.skipped
                summary.podcastsFailed = r.failed
                if !r.failedPodcasts.isEmpty {
                    summary.warnings.append("Could not subscribe to: \(r.failedPodcasts.joined(separator: ", "))")
                }
            }
            // Tell the import sheet PodcastImportManager owns to dismiss itself,
            // since this restore flow drives its own progress sheet.
            PodcastImportManager.shared.dismissImportSheet()
        }

        // 2. Per-podcast settings — apply to the rows that now exist.
        status = "Applying podcast settings…"
        progress = 0.45
        for bp in subscribedPodcasts {
            applyPodcastSettings(bp, in: ctx, warnings: &summary.warnings)
        }

        // 3. Episodes — smart merge by composite id "{podcastTitle}\u{1F}{episodeTitle}".
        status = "Restoring episodes…"
        let totalEpisodes = max(archive.episodes.count, 1)
        for (i, be) in archive.episodes.enumerated() {
            // Hold progress between 0.55 and 0.85 for the episode pass.
            progress = 0.55 + 0.30 * Double(i) / Double(totalEpisodes)
            upsertEpisode(be, in: ctx, summary: &summary)
        }

        // 4. Queue — replace entirely.
        status = "Restoring queue…"
        progress = 0.88
        replaceQueue(with: archive.queue, in: ctx, summary: &summary)

        // 5. AI analyses & quick tags — upsert by (episodeTitle, podcastTitle) /
        //    (episodeAudioURL, episodeTitle).
        status = "Restoring AI analyses…"
        progress = 0.93
        for ba in archive.aiAnalyses {
            upsertAIAnalysis(ba, in: ctx, summary: &summary)
        }

        // 5b. Per-podcast AI "Show Format" hints — restore via existing setter (overwrites on conflict).
        for (podcastTitle, hint) in archive.aiFormatHints {
            AISettingsManager.shared.saveFormatHint(hint, for: podcastTitle)
            summary.formatHintsRestored += 1
        }

        // 6. Settings safelist — write through.
        status = "Applying settings…"
        progress = 0.97
        for (key, value) in archive.settings.values where BackupSettingsSafelist.isAllowed(key) {
            value.write(to: UserDefaults.standard, key: key)
            summary.settingsApplied += 1
        }

        do {
            try ctx.save()
        } catch {
            summary.warnings.append("Save failed: \(error.localizedDescription)")
            logger.error("Restore save failed: \(error.localizedDescription, privacy: .public)")
        }

        progress = 1
        status = "Restore complete"
        lastSummary = summary
        logger.info("Restore done: +\(summary.podcastsAdded) podcasts, \(summary.episodesInserted)/\(summary.episodesUpdated) episodes new/updated, \(summary.queueReplaced) queue, \(summary.warnings.count) warnings.")
    }

    // MARK: - Per-section helpers

    private func applyPodcastSettings(
        _ bp: BackupPodcast,
        in ctx: ModelContext,
        warnings: inout [String]
    ) {
        let rss = bp.rssUrl
        var model = try? ctx.fetch(
            FetchDescriptor<PodcastInfoModel>(predicate: #Predicate { $0.rssUrl == rss })
        ).first

        if model == nil {
            let title = bp.title
            model = try? ctx.fetch(
                FetchDescriptor<PodcastInfoModel>(predicate: #Predicate { $0.title == title })
            ).first
            if model != nil {
                logger.info("Matched '\(bp.title)' by title fallback (RSS URL changed)")
            }
        }

        guard let m = model else {
            warnings.append("Skipping settings for \"\(bp.title)\" — podcast not in library.")
            return
        }

        m.autoTranscribeNewEpisodes = bp.autoTranscribeNewEpisodes
        m.autoDownloadSetting = bp.autoDownloadSetting
        m.episodeFilterInclude = bp.episodeFilterInclude
        m.episodeFilterExclude = bp.episodeFilterExclude
        m.episodeFilterMinDuration = bp.episodeFilterMinDuration
        if let cadence = bp.detectedCadence, m.detectedCadence == nil {
            m.detectedCadence = cadence
        }
        // Preserve the user's original subscribe date when older than the
        // freshly-created model's `dateAdded` (which defaults to Date()).
        if bp.dateAdded < m.dateAdded {
            m.dateAdded = bp.dateAdded
        }
    }

    private func upsertEpisode(
        _ be: BackupEpisode,
        in ctx: ModelContext,
        summary: inout ImportSummary
    ) {
        let key = "\(be.podcastTitle)\u{1F}\(be.episodeTitle)"
        let existing = try? ctx.fetch(
            FetchDescriptor<EpisodeDownloadModel>(predicate: #Predicate { $0.id == key })
        ).first

        guard let e = existing else {
            let m = EpisodeDownloadModel(
                episodeTitle: be.episodeTitle,
                podcastTitle: be.podcastTitle,
                audioURL: be.audioURL,
                lastPlaybackPosition: be.lastPlaybackPosition,
                duration: be.duration,
                isCompleted: be.isCompleted,
                lastPlayedDate: be.lastPlayedDate,
                playCount: be.playCount,
                isStarred: be.isStarred,
                notes: be.notes,
                imageURL: be.imageURL,
                pubDate: be.pubDate,
                autoDownloadEnabled: be.autoDownloadEnabled,
                upNextDismissedAt: be.upNextDismissedAt
            )
            ctx.insert(m)
            summary.episodesInserted += 1
            return
        }

        // Last-played-wins on playback fields.
        let incomingPlayed = be.lastPlayedDate ?? .distantPast
        let existingPlayed = e.lastPlayedDate ?? .distantPast
        if incomingPlayed >= existingPlayed {
            e.lastPlaybackPosition = be.lastPlaybackPosition
            if be.duration > 0 { e.duration = be.duration }
            e.isCompleted = be.isCompleted
            e.lastPlayedDate = be.lastPlayedDate
        }
        e.playCount = max(e.playCount, be.playCount)
        e.isStarred = e.isStarred || be.isStarred
        if e.notes == nil, let n = be.notes, !n.isEmpty { e.notes = n }
        if let dismissed = be.upNextDismissedAt {
            e.upNextDismissedAt = dismissed
        }
        // AntennaPod-style: once auto-download is off, stays off.
        e.autoDownloadEnabled = e.autoDownloadEnabled && be.autoDownloadEnabled
        if e.imageURL == nil, be.imageURL != nil { e.imageURL = be.imageURL }
        if e.pubDate == nil, be.pubDate != nil { e.pubDate = be.pubDate }
        if e.audioURL.isEmpty, !be.audioURL.isEmpty { e.audioURL = be.audioURL }
        summary.episodesUpdated += 1
    }

    private func replaceQueue(
        with items: [BackupQueueItem],
        in ctx: ModelContext,
        summary: inout ImportSummary
    ) {
        let existing = (try? ctx.fetch(FetchDescriptor<QueueItemModel>())) ?? []
        for q in existing { ctx.delete(q) }

        for bq in items.sorted(by: { $0.position < $1.position }) {
            let episode = PlaybackEpisode(
                id: bq.id,
                title: bq.episodeTitle,
                podcastTitle: bq.podcastTitle,
                audioURL: bq.audioURL,
                imageURL: bq.imageURL,
                episodeDescription: bq.episodeDescription,
                pubDate: bq.pubDate,
                duration: bq.duration,
                guid: bq.guid
            )
            ctx.insert(QueueItemModel(from: episode, position: bq.position))
        }
        summary.queueReplaced = items.count
    }

    private func upsertAIAnalysis(
        _ ba: BackupAIAnalysis,
        in ctx: ModelContext,
        summary: inout ImportSummary
    ) {
        let title = ba.episodeTitle
        let podcast = ba.podcastTitle
        let existing = try? ctx.fetch(FetchDescriptor<EpisodeAIAnalysis>(
            predicate: #Predicate { $0.episodeTitle == title && $0.podcastTitle == podcast }
        )).first

        guard let e = existing else {
            let m = EpisodeAIAnalysis(
                episodeAudioURL: ba.episodeAudioURL,
                episodeTitle: ba.episodeTitle,
                podcastTitle: ba.podcastTitle
            )
            m.analysisJSON = ba.analysisJSON
            m.qaHistoryJSON = ba.qaHistoryJSON
            m.provider = ba.provider
            m.model = ba.model
            m.generatedAt = ba.generatedAt
            m.createdAt = ba.createdAt
            m.updatedAt = ba.updatedAt
            ctx.insert(m)
            summary.analysesUpserted += 1
            return
        }

        if ba.updatedAt > e.updatedAt {
            e.analysisJSON = ba.analysisJSON
            e.qaHistoryJSON = ba.qaHistoryJSON
            e.provider = ba.provider
            e.model = ba.model
            e.generatedAt = ba.generatedAt
            e.updatedAt = ba.updatedAt
            summary.analysesUpserted += 1
        }
    }


    func dismissProgressSheet() {
        showProgressSheet = false
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            lastSummary = nil
            lastError = nil
        }
    }
}

// MARK: - DTO ⇄ Model bridges

extension BackupPodcast {
    init(from m: PodcastInfoModel) {
        self.rssUrl = m.rssUrl
        self.title = m.title
        self.imageURL = m.podcastInfo.imageURL
        self.language = m.podcastInfo.language
        self.podcastDescription = m.podcastInfo.podcastInfoDescription
        self.dateAdded = m.dateAdded
        self.isSubscribed = m.isSubscribed
        self.autoTranscribeNewEpisodes = m.autoTranscribeNewEpisodes
        self.autoDownloadSetting = m.autoDownloadSetting
        self.episodeFilterInclude = m.episodeFilterInclude
        self.episodeFilterExclude = m.episodeFilterExclude
        self.episodeFilterMinDuration = m.episodeFilterMinDuration
        self.detectedCadence = m.detectedCadence
    }
}

extension BackupEpisode {
    init(from m: EpisodeDownloadModel) {
        self.podcastTitle = m.podcastTitle
        self.episodeTitle = m.episodeTitle
        self.audioURL = m.audioURL
        self.imageURL = m.imageURL
        self.pubDate = m.pubDate
        self.duration = m.duration
        self.lastPlaybackPosition = m.lastPlaybackPosition
        self.isCompleted = m.isCompleted
        self.lastPlayedDate = m.lastPlayedDate
        self.playCount = m.playCount
        self.isStarred = m.isStarred
        self.notes = m.notes
        self.upNextDismissedAt = m.upNextDismissedAt
        self.autoDownloadEnabled = m.autoDownloadEnabled
    }
}

extension BackupQueueItem {
    init(from m: QueueItemModel) {
        self.position = m.position
        self.id = m.id
        self.episodeTitle = m.episodeTitle
        self.podcastTitle = m.podcastTitle
        self.audioURL = m.audioURL
        self.imageURL = m.imageURL
        self.episodeDescription = m.episodeDescription
        self.pubDate = m.pubDate
        self.duration = m.duration
        self.guid = m.guid
    }
}

extension BackupAIAnalysis {
    init(from m: EpisodeAIAnalysis) {
        self.episodeAudioURL = m.episodeAudioURL
        self.episodeTitle = m.episodeTitle
        self.podcastTitle = m.podcastTitle
        self.analysisJSON = m.analysisJSON
        self.qaHistoryJSON = m.qaHistoryJSON
        self.provider = m.provider
        self.model = m.model
        self.generatedAt = m.generatedAt
        self.createdAt = m.createdAt
        self.updatedAt = m.updatedAt
    }
}


extension BackupSettings {
    /// Read every safelisted UserDefaults key, drop entries the deny list rejects.
    static func snapshotSafe() -> BackupSettings {
        let defaults = UserDefaults.standard
        var out: [String: BackupSettingValue] = [:]
        for key in BackupSettingsSafelist.keys where BackupSettingsSafelist.isAllowed(key) {
            guard let raw = defaults.object(forKey: key) else { continue }
            if let typed = BackupSettingValue.from(raw) {
                out[key] = typed
            }
        }
        return BackupSettings(values: out)
    }
}

// MARK: - Bundle convenience

private extension Bundle {
    var shortVersion: String {
        (object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "unknown"
    }
    var buildNumber: String {
        (object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "unknown"
    }
}
