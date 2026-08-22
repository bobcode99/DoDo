//
//  EpisodeAnalysisModels.swift
//  PodcastAnalyzer
//
//  Models for AI-powered episode analysis
//  - On-device (Apple Foundation Models): episode recommendations from metadata
//  - Cloud (BYOK): Full transcript analysis via user-provided API keys
//

import Foundation
import FoundationModels

// MARK: - On-Device Models

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
