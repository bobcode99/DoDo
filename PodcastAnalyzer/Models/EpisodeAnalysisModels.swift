//
//  EpisodeAnalysisModels.swift
//  PodcastAnalyzer
//
//  Models for AI-powered episode analysis
//  - On-device (Apple Foundation Models): Quick tags from metadata only
//  - Cloud (BYOK): Full transcript analysis via user-provided API keys
//

import Foundation
import FoundationModels

// MARK: - On-Device Models (Quick Tags from Metadata)

/// Quick tags generated from episode metadata (title, description, duration)
/// Used by on-device Foundation Models - lightweight operation within 4096 token limit
@Generable
struct EpisodeQuickTags {
    @Guide(description: "List of 5-8 relevant keywords or tags based on the episode title and description")
    var tags: [String]

    @Guide(description: "Primary category: 'Technology', 'Business', 'Education', 'Health', 'Entertainment', 'News', 'Sports', 'Science', 'Arts', 'Society'")
    var primaryCategory: String

    @Guide(description: "One secondary category if applicable")
    var secondaryCategory: String?

    @Guide(description: "Content type: 'interview', 'solo', 'panel', 'documentary', 'tutorial', 'news', 'storytelling'")
    var contentType: String

    @Guide(description: "Estimated difficulty: 'beginner', 'intermediate', 'advanced'")
    var difficulty: String
}

/// Listening history summary generated on-device from episode metadata
/// Used by Apple Foundation Models - fits within 4096 token limit
@Generable
struct ListeningHistorySummary {
    @Guide(description: "2-3 sentence overview of listening habits")
    var summary: String

    @Guide(description: "Top 3 topics or themes")
    var topTopics: [String]

    @Guide(description: "Total listening time described naturally, e.g. '~12 hours'")
    var totalListeningTime: String

    @Guide(description: "An interesting pattern or insight")
    var insight: String
}

/// Episode recommendations generated on-device based on listening history
/// Used by Apple Foundation Models - fits within 4096 token limit
@Generable
struct EpisodeRecommendations {
    @Guide(description: "The numbers (from the numbered Available episodes list) of the 3-5 best episodes, ordered by relevance")
    var recommendedNumbers: [Int]

    @Guide(description: "Brief reason for each recommended number, in the same order")
    var reasons: [String]
}

// MARK: - Analysis State

/// Represents the state of AI analysis (works for both on-device and cloud)
enum AnalysisState: Equatable {
    case idle
    case analyzing(progress: Double, message: String)
    case completed
    case error(String)

    /// Convenience initializer
    static func analyzing(progress: Double) -> AnalysisState {
        .analyzing(progress: progress, message: "Analyzing...")
    }

    /// Get the progress value if in analyzing state
    var progress: Double? {
        if case .analyzing(let progress, _) = self {
            return progress
        }
        return nil
    }

    /// Get the message if in analyzing state
    var analysisMessage: String? {
        if case .analyzing(_, let message) = self {
            return message
        }
        return nil
    }

    /// Check if currently analyzing
    var isAnalyzing: Bool {
        if case .analyzing = self {
            return true
        }
        return false
    }
}

// MARK: - Cloud Analysis Tab Selection

/// Tabs available for cloud-based transcript analysis
enum CloudAnalysisTab: String, CaseIterable, Identifiable {
    case analysis = "Analysis"
    case askQuestion = "Ask"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .analysis: return "sparkles"
        case .askQuestion: return "questionmark.bubble"
        }
    }

    var description: String {
        switch self {
        case .analysis: return "Unified summary, entities, highlights, quotes, and takeaways"
        case .askQuestion: return "Ask questions about the episode content"
        }
    }

    /// Convert to CloudAnalysisType for the service
    var analysisType: CloudAnalysisType? {
        switch self {
        case .analysis: return .analysis
        case .askQuestion: return nil // Q&A is handled separately
        }
    }
}

// MARK: - Cached Analysis Results

/// Container for cached cloud analysis results
struct CachedCloudAnalysis {
    var analysis: CloudAnalysisResult?
    var questionAnswers: [CloudQAResult] = []

    /// Check if a specific analysis type has been completed
    func hasResult(for type: CloudAnalysisType) -> Bool {
        switch type {
        case .analysis: return analysis != nil
        }
    }

    /// Get result for a specific type
    func result(for type: CloudAnalysisType) -> CloudAnalysisResult? {
        switch type {
        case .analysis: return analysis
        }
    }

    /// Clear all cached results
    mutating func clearAll() {
        analysis = nil
        questionAnswers = []
    }
}

// MARK: - Quick Tags Cache

/// Container for cached on-device quick tags
struct CachedQuickTags {
    var tags: EpisodeQuickTags?
    var briefSummary: String?
    var generatedAt: Date?

    var hasContent: Bool {
        tags != nil || briefSummary != nil
    }

    mutating func clear() {
        tags = nil
        briefSummary = nil
        generatedAt = nil
    }
}
