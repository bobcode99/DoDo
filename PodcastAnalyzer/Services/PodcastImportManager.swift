import Foundation
import SwiftData
import OSLog
import Observation // Required for @Observable

@Observable
@MainActor
class PodcastImportManager {
    static let shared = PodcastImportManager()

    var isImporting = false
    var importProgress: Double = 0
    var importStatus: String = ""
    var importResults: ImportResults?
    var showImportSheet = false

    @ObservationIgnored
    private let rssService = PodcastRssService()

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PodcastImport")

    @ObservationIgnored
    private var modelContext: ModelContext?

    struct ImportResults: Sendable {
        let total: Int
        let successful: Int
        let failed: Int
        let skipped: Int
        let failedPodcasts: [String]
    }

    private init() {
        // Modern Swift 6 approach: Task-based notification observation
        Task {
            for await notification in NotificationCenter.default.notifications(named: .importPodcastsRequested) {
                guard let rssURLs = notification.userInfo?["rssURLs"] as? [String] else { continue }
                await self.importPodcasts(from: rssURLs)
            }
        }
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContext = container.mainContext
    }

    func importPodcasts(from rssURLs: [String]) async {
        guard let context = modelContext else {
            logger.error("ModelContext not set")
            return
        }

        // Reset state
        isImporting = true
        showImportSheet = true
        importProgress = 0
        importStatus = "Starting import..."
        importResults = nil

        var successful = 0
        var failed = 0
        var skipped = 0
        var failedPodcasts: [String] = []

        for (index, rssURL) in rssURLs.enumerated() {
            // Update UI
            importProgress = Double(index) / Double(rssURLs.count)
            importStatus = "Importing \(index + 1) of \(rssURLs.count)..."

            do {
                // Logic optimization: Use a local helper to keep the loop clean
                let result = try await processImport(rssURL: rssURL, context: context)
                switch result {
                case .success: successful += 1
                case .skipped: skipped += 1
                }
            } catch {
                logger.error("Failed to import \(rssURL): \(error.localizedDescription, privacy: .public)")
                failed += 1
                failedPodcasts.append(rssURL)
            }
        }

        // Finalize
        importResults = ImportResults(
            total: rssURLs.count,
            successful: successful,
            failed: failed,
            skipped: skipped,
            failedPodcasts: failedPodcasts
        )
        importProgress = 1.0
        importStatus = "Import complete!"
        isImporting = false
    }

    private enum ImportOutcome { case success, skipped }

    private func processImport(rssURL: String, context: ModelContext) async throws -> ImportOutcome {
        // 1. Check existing URL
        let urlPredicate = #Predicate<PodcastInfoModel> { $0.rssUrl == rssURL }
        let existing = try context.fetch(FetchDescriptor<PodcastInfoModel>(predicate: urlPredicate)).first
        
        if let existing {
            if existing.isSubscribed { return .skipped }
            existing.setSubscribed(true)
            return .success
        }

        // 2. Fetch and check Title (as backup)
        let podcastInfo = try await rssService.fetchPodcast(from: rssURL)
        let title = podcastInfo.title
        let titlePredicate = #Predicate<PodcastInfoModel> { $0.title == title }
        let existingByTitle = try context.fetch(FetchDescriptor<PodcastInfoModel>(predicate: titlePredicate)).first

        if let existingByTitle {
            existingByTitle.setSubscribed(true)
            return .success
        }

        // 3. New Podcast
        let model = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date(), isSubscribed: true)
        context.insert(model)
        try context.save()
        SubscriptionSyncCoordinator.shared.sync(from: model)
        return .success
    }

    func dismissImportSheet() {
        showImportSheet = false
        // Delay clearing results slightly so the sheet animation finishes
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            importResults = nil
        }
    }
}