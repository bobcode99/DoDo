//
//  AIAnalysisModel.swift
//  PodcastAnalyzer
//
//  SwiftData models for persisting AI analysis results
//

import Foundation
import SwiftData

// MARK: - Episode AI Analysis (Cloud)

@Model
final class EpisodeAIAnalysis {
    #Index<EpisodeAIAnalysis>([\.episodeAudioURL], [\.episodeTitle])

    // Link to episode
    var episodeAudioURL: String = ""
    var episodeTitle: String = ""
    var podcastTitle: String = ""

    // Single JSON payload storing the unified ParsedEpisodeAnalysisResponse
    var analysisJSON: String?
    var provider: String?
    var model: String?
    var generatedAt: Date?

    // Q&A history (stored as JSON)
    var qaHistoryJSON: String?

    // Timestamps
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        episodeAudioURL: String,
        episodeTitle: String,
        podcastTitle: String
    ) {
        self.episodeAudioURL = episodeAudioURL
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Convenience Methods

    var hasAnalysis: Bool { analysisJSON != nil }

    /// Decoded unified analysis — encodes/decodes lazily on access
    var parsedAnalysis: ParsedEpisodeAnalysisResponse? {
        get {
            guard let json = analysisJSON,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(ParsedEpisodeAnalysisResponse.self, from: data)
        }
        set {
            guard let value = newValue else {
                analysisJSON = nil
                return
            }
            if let data = try? JSONEncoder().encode(value),
               let json = String(data: data, encoding: .utf8) {
                analysisJSON = json
            }
        }
    }

    // Q&A history as CloudQAResult array
    var qaHistory: [CloudQAResult] {
        get {
            guard let json = qaHistoryJSON,
                  let data = json.data(using: .utf8),
                  let array = try? JSONDecoder().decode([QAEntry].self, from: data) else {
                return []
            }
            return array.map { $0.toCloudQAResult() }
        }
        set {
            let entries = newValue.map { QAEntry(from: $0) }
            if let data = try? JSONEncoder().encode(entries),
               let json = String(data: data, encoding: .utf8) {
                qaHistoryJSON = json
            }
        }
    }

    func addQA(_ result: CloudQAResult) {
        var history = qaHistory
        history.append(result)
        qaHistory = history
        updatedAt = Date()
    }
}

// Helper for Q&A serialization - includes all fields from CloudQAResult
// Marked as Sendable for Swift 6 concurrency safety
struct QAEntry: Codable, Sendable {
    let question: String
    let answer: String
    let confidence: String
    let relatedTopics: [String]?
    let sources: [String]?
    let providerRawValue: String
    let model: String
    let timestamp: Date
    let jsonParseWarning: String?

    nonisolated init(from result: CloudQAResult) {
        self.question = result.question
        self.answer = result.answer
        self.confidence = result.confidence
        self.relatedTopics = result.relatedTopics
        self.sources = result.sources
        self.providerRawValue = result.provider.rawValue
        self.model = result.model
        self.timestamp = result.timestamp
        self.jsonParseWarning = result.jsonParseWarning
    }

    /// Convert back to CloudQAResult - nonisolated for use from any context
    nonisolated func toCloudQAResult() -> CloudQAResult {
        let provider = CloudAIProvider(rawValue: providerRawValue) ?? .gemini
        return CloudQAResult(
            question: question,
            answer: answer,
            confidence: confidence,
            relatedTopics: relatedTopics,
            sources: sources,
            provider: provider,
            model: model,
            timestamp: timestamp,
            jsonParseWarning: jsonParseWarning
        )
    }

    // Legacy initializer for backward compatibility with old data
    init(question: String, answer: String, timestamp: Date) {
        self.question = question
        self.answer = answer
        self.confidence = "unknown"
        self.relatedTopics = nil
        self.sources = nil
        self.providerRawValue = CloudAIProvider.gemini.rawValue
        self.model = "Unknown"
        self.timestamp = timestamp
        self.jsonParseWarning = nil
    }
}

// MARK: - Episode Quick Tags (On-Device)

@Model
final class EpisodeQuickTagsModel {
    #Index<EpisodeQuickTagsModel>([\.episodeAudioURL])

    // Link to episode
    var episodeAudioURL: String = ""
    var episodeTitle: String = ""

    // Tags data
    var tags: [String] = []
    var primaryCategory: String = ""
    var secondaryCategory: String?
    var contentType: String = ""
    var difficulty: String = ""

    // Brief summary
    var briefSummary: String?

    // Timestamps
    var generatedAt: Date = Date()

    init(
        episodeAudioURL: String,
        episodeTitle: String,
        tags: [String],
        primaryCategory: String,
        secondaryCategory: String?,
        contentType: String,
        difficulty: String,
        briefSummary: String? = nil
    ) {
        self.episodeAudioURL = episodeAudioURL
        self.episodeTitle = episodeTitle
        self.tags = tags
        self.primaryCategory = primaryCategory
        self.secondaryCategory = secondaryCategory
        self.contentType = contentType
        self.difficulty = difficulty
        self.briefSummary = briefSummary
        self.generatedAt = Date()
    }
}

// MARK: - Q&A Highlight

/// A structured Q&A pair extracted from a podcast episode
nonisolated struct QAHighlight: Codable, Sendable {
    let question: String
    let answer: String
}

// MARK: - Timestamped Quote

/// A quote with an optional timestamp for playback seeking
nonisolated struct TimestampedQuote: Codable, Sendable {
    let text: String
    let timestamp: String?

    var timeInSeconds: TimeInterval? {
        guard let ts = timestamp else { return nil }
        return TimestampUtils.parseToSeconds(ts)
    }
}

// MARK: - Parsed Response Types (for JSON parsing)

/// Parsed Q&A response from cloud AI
nonisolated struct ParsedQAResponse: Codable {
    let answer: String
    let confidence: String
    let relatedTopics: [String]?
    let sources: [String]?
}

/// Unified transcript analysis response from cloud AI.
nonisolated struct ParsedEpisodeAnalysisResponse: Codable {
    let overview: String
    let mainTopics: [TopicDetail]
    let keyTakeaways: [String]
    let keyInsights: [String]
    let targetAudience: String
    let engagementLevel: String
    let people: [String]
    let organizations: [String]
    let products: [String]
    let locations: [String]
    let resources: [String]
    let highlights: [String]
    let notableQuotes: [TimestampedQuote]
    let actionItems: [String]
    let controversialPoints: [String]?
    let entertainingMoments: [String]?
    let qaHighlights: [QAHighlight]?
    let conclusion: String

    nonisolated struct TopicDetail: Codable {
        let topic: String
        let summary: String
        let keyPoints: [String]
    }

    init(
        overview: String,
        mainTopics: [TopicDetail],
        keyTakeaways: [String],
        keyInsights: [String],
        targetAudience: String,
        engagementLevel: String,
        people: [String],
        organizations: [String],
        products: [String],
        locations: [String],
        resources: [String],
        highlights: [String],
        notableQuotes: [TimestampedQuote],
        actionItems: [String],
        controversialPoints: [String]?,
        entertainingMoments: [String]?,
        qaHighlights: [QAHighlight]? = nil,
        conclusion: String
    ) {
        self.overview = overview
        self.mainTopics = mainTopics
        self.keyTakeaways = keyTakeaways
        self.keyInsights = keyInsights
        self.targetAudience = targetAudience
        self.engagementLevel = engagementLevel
        self.people = people
        self.organizations = organizations
        self.products = products
        self.locations = locations
        self.resources = resources
        self.highlights = highlights
        self.notableQuotes = notableQuotes
        self.actionItems = actionItems
        self.controversialPoints = controversialPoints
        self.entertainingMoments = entertainingMoments
        self.qaHighlights = qaHighlights
        self.conclusion = conclusion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        overview = try container.decode(String.self, forKey: .overview)
        mainTopics = try container.decode([TopicDetail].self, forKey: .mainTopics)
        keyTakeaways = try container.decodeIfPresent([String].self, forKey: .keyTakeaways) ?? []
        keyInsights = try container.decodeIfPresent([String].self, forKey: .keyInsights) ?? []
        targetAudience = try container.decodeIfPresent(String.self, forKey: .targetAudience) ?? ""
        engagementLevel = try container.decodeIfPresent(String.self, forKey: .engagementLevel) ?? ""
        people = try container.decodeIfPresent([String].self, forKey: .people) ?? []
        organizations = try container.decodeIfPresent([String].self, forKey: .organizations) ?? []
        products = try container.decodeIfPresent([String].self, forKey: .products) ?? []
        locations = try container.decodeIfPresent([String].self, forKey: .locations) ?? []
        resources = try container.decodeIfPresent([String].self, forKey: .resources) ?? []
        highlights = try container.decodeIfPresent([String].self, forKey: .highlights) ?? []
        if let items = try container.decodeIfPresent([String].self, forKey: .actionItems) {
            actionItems = items
        } else if let advice = try container.decodeIfPresent([String].self, forKey: .actionableAdvice) {
            actionItems = advice
        } else {
            actionItems = []
        }
        controversialPoints = try container.decodeIfPresent([String].self, forKey: .controversialPoints)
        entertainingMoments = try container.decodeIfPresent([String].self, forKey: .entertainingMoments)
        qaHighlights = try container.decodeIfPresent([QAHighlight].self, forKey: .qaHighlights)
        conclusion = try container.decode(String.self, forKey: .conclusion)

        if let quotes = try? container.decode([TimestampedQuote].self, forKey: .notableQuotes) {
            notableQuotes = quotes
        } else if let strings = try? container.decode([String].self, forKey: .notableQuotes) {
            notableQuotes = strings.map { TimestampedQuote(text: $0, timestamp: nil) }
        } else {
            notableQuotes = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(overview, forKey: .overview)
        try container.encode(mainTopics, forKey: .mainTopics)
        try container.encode(keyTakeaways, forKey: .keyTakeaways)
        try container.encode(keyInsights, forKey: .keyInsights)
        try container.encode(targetAudience, forKey: .targetAudience)
        try container.encode(engagementLevel, forKey: .engagementLevel)
        try container.encode(people, forKey: .people)
        try container.encode(organizations, forKey: .organizations)
        try container.encode(products, forKey: .products)
        try container.encode(locations, forKey: .locations)
        try container.encode(resources, forKey: .resources)
        try container.encode(highlights, forKey: .highlights)
        try container.encode(notableQuotes, forKey: .notableQuotes)
        try container.encode(actionItems, forKey: .actionItems)
        try container.encodeIfPresent(controversialPoints, forKey: .controversialPoints)
        try container.encodeIfPresent(entertainingMoments, forKey: .entertainingMoments)
        try container.encodeIfPresent(qaHighlights, forKey: .qaHighlights)
        try container.encode(conclusion, forKey: .conclusion)
    }

    private enum CodingKeys: String, CodingKey {
        case overview
        case mainTopics
        case keyTakeaways
        case keyInsights
        case targetAudience
        case engagementLevel
        case people
        case organizations
        case products
        case locations
        case resources
        case highlights
        case notableQuotes
        case actionItems
        case actionableAdvice  // decode-only alias for actionItems
        case controversialPoints
        case entertainingMoments
        case qaHighlights
        case conclusion
    }

    // MARK: - Shareable Text

    func formatAsShareableText(episodeTitle: String, podcastTitle: String) -> String {
        var lines: [String] = []
        lines.append("\(episodeTitle)")
        lines.append("\(podcastTitle)")
        lines.append(String(repeating: "─", count: 30))

        lines.append("")
        lines.append("Overview")
        lines.append(overview)

        if !keyTakeaways.isEmpty {
            lines.append("")
            lines.append("Key Takeaways")
            for item in keyTakeaways { lines.append("  - \(item)") }
        }

        if !mainTopics.isEmpty {
            lines.append("")
            lines.append("Main Topics")
            for topic in mainTopics {
                lines.append("  \(topic.topic)")
                lines.append("  \(topic.summary)")
                for point in topic.keyPoints { lines.append("    - \(point)") }
            }
        }

        if !keyInsights.isEmpty {
            lines.append("")
            lines.append("Key Insights")
            for item in keyInsights { lines.append("  - \(item)") }
        }

        func entityBlock(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            lines.append("")
            lines.append(title)
            lines.append("  \(items.joined(separator: ", "))")
        }
        entityBlock("People", people)
        entityBlock("Organizations", organizations)
        entityBlock("Products", products)
        entityBlock("Locations", locations)
        entityBlock("Resources", resources)

        if !highlights.isEmpty {
            lines.append("")
            lines.append("Highlights")
            for item in highlights { lines.append("  - \(item)") }
        }

        if !notableQuotes.isEmpty {
            lines.append("")
            lines.append("Notable Quotes")
            for quote in notableQuotes {
                let ts = quote.timestamp.map { " [\($0)]" } ?? ""
                lines.append("  \"\(quote.text)\"\(ts)")
            }
        }

        if !actionItems.isEmpty {
            lines.append("")
            lines.append("Action Items")
            for item in actionItems { lines.append("  - \(item)") }
        }

        if let controversial = controversialPoints, !controversial.isEmpty {
            lines.append("")
            lines.append("Controversial Points")
            for item in controversial { lines.append("  - \(item)") }
        }

        if let entertaining = entertainingMoments, !entertaining.isEmpty {
            lines.append("")
            lines.append("Entertaining Moments")
            for item in entertaining { lines.append("  - \(item)") }
        }

        if let qa = qaHighlights, !qa.isEmpty {
            lines.append("")
            lines.append("Q&A Highlights")
            for item in qa {
                lines.append("  Q: \(item.question)")
                lines.append("  A: \(item.answer)")
            }
        }

        lines.append("")
        lines.append("Conclusion")
        lines.append(conclusion)

        if !targetAudience.isEmpty {
            lines.append("")
            lines.append("Target Audience: \(targetAudience)")
        }
        if !engagementLevel.isEmpty {
            lines.append("Engagement: \(engagementLevel.capitalized)")
        }

        return lines.joined(separator: "\n")
    }
}
