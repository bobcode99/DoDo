//
//  AppleFoundationModelsService.swift
//  PodcastAnalyzer
//
//  On-device AI using Apple Foundation Models (iOS/macOS 26+).
//
//  Scope is deliberately narrow: episode *recommendations* from titles and short
//  descriptions. Transcript analysis goes through CloudAIService with the user's
//  own API key — the on-device context window is ~4096 tokens, which a real
//  transcript blows past immediately.
//
//  Quick tags, brief summaries and a listening-history summary used to live here.
//  The first two lost their UI in a January 2026 refactor and the third never had
//  a caller, so all three were removed rather than left to rot as dead prompts.
//

import Foundation
import FoundationModels
import OSLog

private nonisolated let logger = Logger(subsystem: "com.podcast.analyzer", category: "AppleFoundationModelsService")

@available(iOS 26.0, macOS 26.0, *)
actor AppleFoundationModelsService {

    // MARK: - Properties

    private let session: LanguageModelSession

    // MARK: - Initialization

    init() {
        // Instructions describe recommending, because recommending is what this
        // session is asked to do. It previously claimed to be a "podcast
        // categorization assistant" — left over from the tagging feature — and
        // the recommendation call inherited that framing.
        self.session = LanguageModelSession(instructions: """
            You recommend podcast episodes to a listener.

            Given what someone has already listened to, judge which of the
            available episodes they are most likely to enjoy, and say briefly why
            in their own words. Prefer episodes that continue an interest the
            history shows. Do not recommend an episode that is already in the
            history.
            """)
    }

    // MARK: - Availability Checking

    /// Whether the system model can run right now.
    func checkAvailability() -> FoundationModelsAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable(.modelNotReady):
            return .unavailable(.modelNotReady)
        case .unavailable(_):
            return .unavailable(.other)
        }
    }

    // MARK: - Episode Recommendations

    /// Rank candidate episodes against listening history.
    ///
    /// - Parameter language: the podcast's language, so reasons come back in the
    ///   language the listener actually reads. Without it a CJK library is
    ///   described back to the user in English.
    func generateEpisodeRecommendations(
        listeningHistory: [(title: String, podcastTitle: String, completed: Bool)],
        availableEpisodes: [(title: String, podcastTitle: String, description: String)],
        language: String? = nil,
        progressCallback: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> EpisodeRecommendations {
        logger.info("Generating recommendations from \(listeningHistory.count) history + \(availableEpisodes.count) available episodes")

        progressCallback?("Preparing episode data...", 0.2)

        let historyList = Array(listeningHistory.prefix(Self.maxHistory)).enumerated().map { index, ep in
            let status = ep.completed ? "finished" : "started"
            return "\(index + 1). \"\(ep.title)\" from \(ep.podcastTitle) (\(status))"
        }.joined(separator: "\n")

        let availableList = Array(availableEpisodes.prefix(Self.maxCandidates)).enumerated().map { index, ep in
            let desc = ep.description.count > Self.descriptionLimit
                ? String(ep.description.prefix(Self.descriptionLimit)) + "..."
                : ep.description
            return "\(index + 1). \"\(ep.title)\" from \(ep.podcastTitle) - \(desc)"
        }.joined(separator: "\n")

        progressCallback?("Finding best matches...", 0.5)

        let languageLine = language.flatMap { code -> String? in
            guard !code.isEmpty,
                  let name = Locale.current.localizedString(forLanguageCode: code)
            else { return nil }
            return "\n\nWrite each reason in \(name)."
        } ?? ""

        let prompt = """
        Based on what I've listened to, rank which available episodes I'd enjoy most.

        My listening history:
        \(historyList)

        Available episodes:
        \(availableList)

        Reply with the numbers (from the Available episodes list) of the 3-5 \
        episodes I'd enjoy most, ordered best first, and one short reason for \
        each — under 12 words, naming what connects it to my history.\(languageLine)
        """

        let response = try await session.respond(to: prompt, generating: EpisodeRecommendations.self)

        progressCallback?("Done", 1.0)
        logger.info("Episode recommendations generated successfully")

        return response.content
    }

    // MARK: - Limits

    /// How much history the model sees. Beyond this the prompt crowds out the
    /// candidate list, which is the half that actually gets picked from.
    static let maxHistory = 10
    /// Candidates offered per run.
    static let maxCandidates = 15
    /// Description budget per candidate. 100 characters was usually just the
    /// sponsor boilerplate every episode of a show opens with.
    static let descriptionLimit = 240
}

// MARK: - Availability

/// Why the on-device model can't run.
///
/// A case rather than a `String`: these are shown in Settings, and as free-form
/// English they could never reach the string catalog. The view maps them to
/// localized text.
enum FoundationModelsUnavailableReason: Equatable {
    case appleIntelligenceNotEnabled
    case deviceNotEligible
    case modelNotReady
    case other
}

enum FoundationModelsAvailability: Equatable {
    /// Nothing has been checked yet. Distinct from `.unavailable` so the UI can
    /// render a neutral "checking" row rather than a warning for a check that
    /// hasn't run.
    case checking
    case available
    case unavailable(FoundationModelsUnavailableReason)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    var reason: FoundationModelsUnavailableReason? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}
