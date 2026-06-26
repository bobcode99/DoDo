//
//  AppleFoundationModelsService.swift
//  PodcastAnalyzer
//
//  Service for on-device AI using Apple Foundation Models (iOS 26+)
//  Used for quick tags, categorization, and brief summaries from episode metadata
//  For full transcript analysis, use CloudAIService with user-provided API keys
//

import Foundation
import FoundationModels
import OSLog

private nonisolated let logger = Logger(subsystem: "com.podcast.analyzer", category: "AppleFoundationModelsService")

/// Service for on-device AI features using Apple Foundation Models (iOS 26+)
/// Uses only episode title, description, duration, and release date - NOT the full transcript
/// This keeps requests well within the 4096 token context limit
@available(iOS 26.0, macOS 26.0, *)
actor AppleFoundationModelsService {

    // MARK: - Properties

    private let session: LanguageModelSession

    // MARK: - Initialization

    init() {
        self.session = LanguageModelSession(instructions: """
            You are a podcast categorization assistant. Your role is to generate relevant tags and categories
            based on episode metadata (title, description, duration, release date).

            Be concise and accurate. Generate tags that help users discover and organize episodes.
            Focus on topics, themes, genres, and content types.
            """)
    }

    // MARK: - Availability Checking

    /// Check if Foundation Models are available on this device
    func checkAvailability() -> FoundationModelsAvailability {
        let systemModel = SystemLanguageModel.default

        switch systemModel.availability {
        case .available:
            return .available

        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Apple Intelligence is not enabled. Please enable it in Settings → Apple Intelligence & Siri.")

        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This device doesn't support Apple Intelligence. Requires iPhone 15 Pro or newer, or M1+ Mac/iPad.")

        case .unavailable(.modelNotReady):
            return .unavailable(reason: "The AI model is downloading. This may take a few minutes.")

        case .unavailable(_):
            return .unavailable(reason: "Apple Intelligence is currently unavailable.")
        }
    }

    // MARK: - Quick Tag Generation (On-Device)

    /// Generate quick tags from episode metadata (NOT the transcript)
    /// This is lightweight and fits within the on-device context limit
    /// - Parameters:
    ///   - title: Episode title
    ///   - description: Episode description (will be truncated if too long)
    ///   - podcastTitle: Name of the podcast
    ///   - duration: Episode duration in seconds (optional)
    ///   - releaseDate: Episode release date (optional)
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Quick tags and categories
    func generateQuickTags(
        title: String,
        description: String,
        podcastTitle: String,
        duration: TimeInterval? = nil,
        releaseDate: Date? = nil,
        progressCallback: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> EpisodeQuickTags {
        logger.info("Generating quick tags for: \(title)")

        progressCallback?("Preparing metadata...", 0.2)

        // Truncate description to ~500 chars to stay well within limits
        let truncatedDescription = description.count > 500
            ? String(description.prefix(500)) + "..."
            : description

        // Format duration
        let durationString: String
        if let duration = duration {
            let minutes = Int(duration) / 60
            durationString = "\(minutes) minutes"
        } else {
            durationString = "unknown duration"
        }

        // Format release date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let releaseDateString = releaseDate.map { dateFormatter.string(from: $0) } ?? "unknown date"

        progressCallback?("Generating tags...", 0.5)

        let prompt = """
        Generate tags and categories for this podcast episode:

        Podcast: \(podcastTitle)
        Episode: \(title)
        Duration: \(durationString)
        Released: \(releaseDateString)

        Description:
        \(truncatedDescription)
        """

        let response = try await session.respond(to: prompt, generating: EpisodeQuickTags.self)

        progressCallback?("Done", 1.0)
        logger.info("Quick tags generated successfully")

        return response.content
    }

    // MARK: - Listening History Summary (On-Device)

    /// Generate a summary of the user's listening history
    /// Takes up to ~20 most recent listened episodes (title, podcast, duration, playCount, completion status)
    /// Fits within 4096 tokens since each episode is ~30 tokens of metadata
    func generateListeningHistorySummary(
        episodes: [(title: String, podcastTitle: String, duration: TimeInterval, playCount: Int, isCompleted: Bool, lastPlayedDate: Date?)],
        progressCallback: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> ListeningHistorySummary {
        logger.info("Generating listening history summary for \(episodes.count) episodes")

        progressCallback?("Preparing listening data...", 0.2)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        // Build episode list string (limit to 20 episodes)
        let limitedEpisodes = Array(episodes.prefix(20))
        let episodeList = limitedEpisodes.enumerated().map { index, ep in
            let minutes = Int(ep.duration) / 60
            let status = ep.isCompleted ? "completed" : "in progress"
            let lastPlayed = ep.lastPlayedDate.map { dateFormatter.string(from: $0) } ?? "unknown"
            return "\(index + 1). \"\(ep.title)\" from \(ep.podcastTitle) (\(minutes) min, \(status), played \(ep.playCount)x, last: \(lastPlayed))"
        }.joined(separator: "\n")

        progressCallback?("Analyzing listening patterns...", 0.5)

        let prompt = """
        Analyze this podcast listening history and summarize the user's listening habits:

        \(episodeList)

        Identify patterns, favorite topics, total approximate listening time, and any interesting insights.
        """

        let response = try await session.respond(to: prompt, generating: ListeningHistorySummary.self)

        progressCallback?("Done", 1.0)
        logger.info("Listening history summary generated successfully")

        return response.content
    }

    // MARK: - Episode Recommendations (On-Device)

    /// Generate personalized episode recommendations based on listening history
    /// Takes ~10 recently listened episodes + ~15 available (unplayed) episodes
    /// Each episode uses ~40 tokens → total ~1000 tokens, well within 4096 limit
    func generateEpisodeRecommendations(
        listeningHistory: [(title: String, podcastTitle: String, completed: Bool)],
        availableEpisodes: [(title: String, podcastTitle: String, description: String)],
        progressCallback: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> EpisodeRecommendations {
        logger.info("Generating recommendations from \(listeningHistory.count) history + \(availableEpisodes.count) available episodes")

        progressCallback?("Preparing episode data...", 0.2)

        // Build listening history string (limit to 10)
        let historyList = Array(listeningHistory.prefix(10)).enumerated().map { index, ep in
            let status = ep.completed ? "finished" : "started"
            return "\(index + 1). \"\(ep.title)\" from \(ep.podcastTitle) (\(status))"
        }.joined(separator: "\n")

        // Build available episodes string (limit to 15, truncate descriptions)
        let availableList = Array(availableEpisodes.prefix(15)).enumerated().map { index, ep in
            let desc = ep.description.count > 100 ? String(ep.description.prefix(100)) + "..." : ep.description
            return "\(index + 1). \"\(ep.title)\" from \(ep.podcastTitle) - \(desc)"
        }.joined(separator: "\n")

        progressCallback?("Finding best matches...", 0.5)

        let prompt = """
        Based on what I've listened to, rank which available episodes I'd enjoy most.

        My listening history:
        \(historyList)

        Available episodes:
        \(availableList)

        Reply with the numbers (from the Available episodes list) of the 3-5 episodes I'd enjoy most, ordered best first.
        """

        let response = try await session.respond(to: prompt, generating: EpisodeRecommendations.self)

        progressCallback?("Done", 1.0)
        logger.info("Episode recommendations generated successfully")

        return response.content
    }

    /// Generate a brief one-line summary from episode metadata
    /// - Parameters:
    ///   - title: Episode title
    ///   - description: Episode description
    ///   - progressCallback: Optional callback for progress updates
    /// - Returns: Brief one-line summary
    func generateBriefSummary(
        title: String,
        description: String,
        progressCallback: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> String {
        logger.info("Generating brief summary for: \(title)")

        progressCallback?("Creating summary...", 0.3)

        // Truncate description to ~800 chars
        let truncatedDescription = description.count > 800
            ? String(description.prefix(800)) + "..."
            : description

        let prompt = """
        Write a single sentence (max 100 words) summarizing this podcast episode based on its title and description:

        Title: \(title)
        Description: \(truncatedDescription)

        Respond with ONLY the summary sentence, nothing else.
        """

        let response = try await session.respond(to: prompt)

        progressCallback?("Done", 1.0)
        logger.info("Brief summary generated successfully")

        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Supporting Types

/// Availability status for Foundation Models
enum FoundationModelsAvailability: Equatable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var message: String? {
        if case .unavailable(let reason) = self {
            return reason
        }
        return nil
    }
}
