//
//  PodcastAppIntents.swift
//  PodcastAnalyzer
//
//  AppIntents for Shortcuts integration - enables Apple Intelligence via Shortcuts
//  Users can create Shortcuts that use Apple Intelligence to analyze transcripts
//

import SwiftData
import AppIntents
import Foundation

// MARK: - Import Podcasts Intent

/// Intent that allows Shortcuts to import podcasts from Apple Podcasts export
/// Accepts combined text with RSS URLs and subscribes to all podcasts
@available(iOS 16.0, macOS 13.0, *)
struct ImportPodcastsIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Podcasts from List"
    static let description = IntentDescription(
        "Import and subscribe to podcasts from an Apple Podcasts export list. Pass the combined text containing RSS feed URLs."
    )

    @Parameter(title: "Combined Text", description: "The exported podcast list containing RSS feed URLs")
    var combinedText: String

    static var parameterSummary: some ParameterSummary {
        Summary("Import podcasts from \(\.$combinedText)")
    }

    // Opens the app when this intent runs
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Parse the combined text to extract RSS URLs
        let rssURLs = parseRSSURLs(from: combinedText)

        if rssURLs.isEmpty {
            return .result(value: "No RSS feed URLs found in the provided text.")
        }

        // Post notification to trigger import in the app
        NotificationCenter.default.post(
            name: .importPodcastsRequested,
            object: nil,
            userInfo: ["rssURLs": rssURLs]
        )

        return .result(value: "Importing \(rssURLs.count) podcasts. Please wait...")
    }

    private func parseRSSURLs(from text: String) -> [String] {
        var urls: [String] = []
        let lines = text.components(separatedBy: .newlines)

        var inURLSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "__PodcastFeedURLs__" {
                inURLSection = true
                continue
            }

            if trimmed == "__PodcastNames__" {
                inURLSection = false
                continue
            }

            if inURLSection && !trimmed.isEmpty {
                // Validate it looks like a URL
                if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                    urls.append(trimmed)
                }
            }
        }

        return urls
    }
}

// MARK: - Analyze Transcript Intent

/// Intent that allows Shortcuts to analyze podcast transcripts
/// Users can create a Shortcut with Apple Intelligence actions and connect it here
@available(iOS 16.0, macOS 13.0, *)
struct AnalyzeTranscriptIntent: AppIntent {
    static let title: LocalizedStringResource = "Analyze Podcast Transcript"
    static let description = IntentDescription(
        "Analyze a podcast transcript using AI. Connect this to an Apple Intelligence action in Shortcuts."
    )

    @Parameter(title: "Transcript Text", description: "The transcript text to analyze")
    var transcript: String

    @Parameter(title: "Episode Title", description: "The podcast episode title")
    var episodeTitle: String

    @Parameter(title: "Podcast Name", description: "The podcast name")
    var podcastName: String

    @Parameter(title: "Analysis Type", description: "Type of analysis to perform")
    var analysisType: AnalysisTypeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Analyze \(\.$episodeTitle) transcript") {
            \.$transcript
            \.$podcastName
            \.$analysisType
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // This intent receives the transcript and analysis type
        // It should be connected to an Apple Intelligence action in Shortcuts
        // The Shortcut will process and return the result

        let prompt = buildPrompt(for: analysisType.type, transcript: transcript, episodeTitle: episodeTitle, podcastName: podcastName)

        // Return the formatted prompt for Apple Intelligence to process
        // Users will connect this to "Ask ChatGPT/Apple Intelligence" action
        return .result(value: prompt)
    }

    private func buildPrompt(for type: ShortcutAnalysisType, transcript: String, episodeTitle: String, podcastName: String) -> String {
        switch type {
        case .summary:
            return """
            Please provide a comprehensive summary of this podcast episode.

            Podcast: \(podcastName)
            Episode: \(episodeTitle)

            Transcript:
            \(transcript)

            Provide:
            1. A 2-3 paragraph summary
            2. Main topics discussed (bullet points)
            3. Key takeaways (bullet points)
            4. Who would benefit from this episode
            """

        case .highlights:
            return """
            Please identify the key highlights from this podcast episode.

            Podcast: \(podcastName)
            Episode: \(episodeTitle)

            Transcript:
            \(transcript)

            Provide:
            1. Top 5 highlights or key moments
            2. The best quote from the episode
            3. Any action items mentioned
            4. Interesting or surprising facts
            """

        case .entities:
            return """
            Please extract all named entities from this podcast episode.

            Podcast: \(podcastName)
            Episode: \(episodeTitle)

            Transcript:
            \(transcript)

            List:
            1. People mentioned (names, roles if known)
            2. Organizations or companies
            3. Products or services
            4. Locations
            5. Books, articles, or resources mentioned
            """

        case .fullAnalysis:
            return """
            Please provide a complete analysis of this podcast episode.

            Podcast: \(podcastName)
            Episode: \(episodeTitle)

            Transcript:
            \(transcript)

            Provide a comprehensive analysis including:
            1. Executive Summary (2-3 paragraphs)
            2. Main Topics Discussed (with details)
            3. Key Insights and Learnings
            4. Notable Quotes
            5. Actionable Advice (if any)
            6. People and Organizations Mentioned
            7. Conclusion and Recommendations
            """

        case .askQuestion:
            return """
            Based on this podcast transcript, please answer questions about the content.

            Podcast: \(podcastName)
            Episode: \(episodeTitle)

            Transcript:
            \(transcript)

            (User will ask their question after this prompt)
            """
        }
    }
}

// MARK: - Get Transcript Intent

/// Intent to get the current episode's transcript for use in Shortcuts
@available(iOS 16.0, macOS 13.0, *)
struct GetCurrentTranscriptIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Current Transcript"
    static let description = IntentDescription(
        "Get the transcript of the currently playing podcast episode"
    )

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Get the current episode's transcript from the audio manager
        let transcript = await getCurrentTranscript()
        return .result(value: transcript)
    }

    @MainActor
    private func getCurrentTranscript() -> String {
        guard let episode = EnhancedAudioManager.shared.currentEpisode else {
            return "No episode is currently playing."
        }

        // Try to load transcript from file.
        // Path: Captions/{sanitizedPodcast}/{sanitizedEpisode}.srt
        let fm = FileManager.default
        let docsDir = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let captionsDir = docsDir.appendingPathComponent("Captions")

        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let sanitizedPodcast = episode.podcastTitle
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
        let sanitizedEpisode = episode.title
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)

        let srtPath = captionsDir
            .appendingPathComponent(sanitizedPodcast, isDirectory: true)
            .appendingPathComponent("\(sanitizedEpisode).srt")

        if let content = try? String(contentsOf: srtPath, encoding: .utf8) {
            // Parse SRT to plain text
            return parseSRTToText(content)
        }

        return "No transcript available for this episode."
    }

    private func parseSRTToText(_ srt: String) -> String {
        let lines = srt.components(separatedBy: .newlines)
        var textLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip index numbers and timestamps
            if trimmed.isEmpty { continue }
            if Int(trimmed) != nil { continue }
            if trimmed.contains("-->") { continue }
            textLines.append(trimmed)
        }

        return textLines.joined(separator: " ")
    }
}

// MARK: - Save Analysis Result Intent

/// Intent to receive analysis results back from Shortcuts
@available(iOS 16.0, macOS 13.0, *)
struct SaveAnalysisResultIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Analysis Result"
    static let description = IntentDescription(
        "Save the AI analysis result back to the podcast episode"
    )

    @Parameter(title: "Analysis Result", description: "The AI-generated analysis text")
    var analysisResult: String

    @Parameter(title: "Analysis Type", description: "Type of analysis performed")
    var analysisType: AnalysisTypeEntity

    func perform() async throws -> some IntentResult {
        // Save the result to the shared cache or notify the app
        await saveAnalysisResult(analysisResult, type: analysisType.type)
        return .result()
    }

    @MainActor
    private func saveAnalysisResult(_ result: String, type: ShortcutAnalysisType) {
        // Post notification with the result
        NotificationCenter.default.post(
            name: .shortcutsAnalysisCompleted,
            object: nil,
            userInfo: [
                "result": result,
                "analysisType": type.rawValue
            ]
        )
    }
}

// MARK: - Analysis Type Entity

enum ShortcutAnalysisType: String, Codable, CaseIterable, Sendable {
    case summary = "Summary"
    case highlights = "Highlights"
    case entities = "Entities"
    case fullAnalysis = "Full Analysis"
    case askQuestion = "Ask Question"
}

@available(iOS 16.0, macOS 13.0, *)
struct AnalysisTypeEntity: AppEntity, Sendable {
    var id: String { type.rawValue }
    var type: ShortcutAnalysisType

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Analysis Type")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(type.rawValue)")
    }

    static var defaultQuery: AnalysisTypeQuery { AnalysisTypeQuery() }

    init(type: ShortcutAnalysisType) {
        self.type = type
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct AnalysisTypeQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AnalysisTypeEntity] {
        identifiers.compactMap { id in
            ShortcutAnalysisType(rawValue: id).map { AnalysisTypeEntity(type: $0) }
        }
    }

    func suggestedEntities() async throws -> [AnalysisTypeEntity] {
        ShortcutAnalysisType.allCases.map { AnalysisTypeEntity(type: $0) }
    }

    func defaultResult() async -> AnalysisTypeEntity? {
        AnalysisTypeEntity(type: .summary)
    }
}

// MARK: - Siri Playback Intents

/// Intent to play the last episode or resume playback
@available(iOS 16.0, macOS 13.0, *)
struct PlayLastEpisodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Play My Podcast"
    static let description = IntentDescription(
        "Resume playback of the last podcast episode or start a new one"
    )

    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let audioManager = EnhancedAudioManager.shared

        // If nothing is loaded, try to restore the last episode
        if audioManager.currentEpisode == nil {
            audioManager.restoreLastEpisode()
        }

        // Resume playback
        audioManager.resume()

        return .result()
    }
}

/// Intent to play or pause the current episode
@available(iOS 16.0, macOS 13.0, *)
struct PlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play/Pause Podcast"
    static let description = IntentDescription(
        "Toggle playback of the current podcast episode"
    )

    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let audioManager = EnhancedAudioManager.shared

        if audioManager.isPlaying {
            audioManager.pause()
        } else {
            // If nothing is loaded, try to restore the last episode first
            if audioManager.currentEpisode == nil {
                audioManager.restoreLastEpisode()
            }
            audioManager.resume()
        }

        return .result()
    }
}

/// Intent to pause playback
@available(iOS 16.0, macOS 13.0, *)
struct PausePodcastIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Podcast"
    static let description = IntentDescription(
        "Pause the currently playing podcast episode"
    )

    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        EnhancedAudioManager.shared.pause()
        return .result()
    }
}

/// Intent to skip forward in the current episode
@available(iOS 16.0, macOS 13.0, *)
struct SkipForwardIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Forward"
    static let description = IntentDescription(
        "Skip forward 15 seconds in the current episode"
    )

    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        EnhancedAudioManager.shared.skipForward()
        return .result()
    }
}

/// Intent to skip backward in the current episode
@available(iOS 16.0, macOS 13.0, *)
struct SkipBackwardIntent: AppIntent {
    static let title: LocalizedStringResource = "Skip Backward"
    static let description = IntentDescription(
        "Skip backward 15 seconds in the current episode"
    )

    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        EnhancedAudioManager.shared.skipBackward()
        return .result()
    }
}

// MARK: - App Shortcuts Provider

@available(iOS 16.0, macOS 13.0, *)
struct PodcastAnalyzerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayLastEpisodeIntent(),
            phrases: [
                "Play my podcast with \(.applicationName)",
                "Resume podcast in \(.applicationName)",
                "Play podcast using \(.applicationName)",
                "Continue listening with \(.applicationName)"
            ],
            shortTitle: "Play Podcast",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: PlayPauseIntent(),
            phrases: [
                "Play pause \(.applicationName)",
                "Toggle playback in \(.applicationName)"
            ],
            shortTitle: "Play/Pause",
            systemImageName: "playpause.fill"
        )

        AppShortcut(
            intent: PausePodcastIntent(),
            phrases: [
                "Pause \(.applicationName)",
                "Stop podcast in \(.applicationName)"
            ],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )

        AppShortcut(
            intent: ImportPodcastsIntent(),
            phrases: [
                "Import podcasts to \(.applicationName)",
                "Import podcast list with \(.applicationName)",
                "Subscribe to podcasts using \(.applicationName)",
                "Import Apple Podcasts to \(.applicationName)"
            ],
            shortTitle: "Import Podcasts",
            systemImageName: "square.and.arrow.down"
        )

        AppShortcut(
            intent: GetCurrentTranscriptIntent(),
            phrases: [
                "Get transcript from \(.applicationName)",
                "Get podcast transcript with \(.applicationName)",
                "Get current episode transcript using \(.applicationName)"
            ],
            shortTitle: "Get Transcript",
            systemImageName: "doc.text"
        )

        AppShortcut(
            intent: AnalyzeTranscriptIntent(),
            phrases: [
                "Analyze podcast with \(.applicationName)",
                "Summarize podcast episode using \(.applicationName)",
                "Analyze transcript in \(.applicationName)"
            ],
            shortTitle: "Analyze Transcript",
            systemImageName: "sparkles"
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let shortcutsAnalysisCompleted = Notification.Name("shortcutsAnalysisCompleted")
    static let shortcutsAnalysisRequested = Notification.Name("shortcutsAnalysisRequested")
    static let importPodcastsRequested = Notification.Name("importPodcastsRequested")
}
