//
//  ShortcutsClient.swift
//  PodcastAnalyzer
//
//  Thin wrapper for Apple PCC / Shortcuts integration.
//  Shortcuts is handled specially in CloudAIService (not via this protocol's send methods),
//  so sendRequest/sendStreamingRequest throw — they should never be called.
//


import Foundation
nonisolated struct ShortcutsClient: AIProviderClient {
    let provider: CloudAIProvider
    let requiresAPIKey: Bool = false

    func fetchAvailableModels(apiKey: String) async throws -> [String] {
        ["Shortcuts"]
    }

    func ping(apiKey: String) async throws {
        // Shortcuts doesn't need a connection test
    }

    func sendRequest(
        prompt: String, systemPrompt: String, apiKey: String, model: String, maxTokens: Int
    ) async throws -> String {
        throw CloudAIError.apiError(statusCode: 0, message: "Apple PCC uses Shortcuts for processing")
    }

    func sendStreamingRequest(
        prompt: String, systemPrompt: String, apiKey: String, model: String, maxTokens: Int,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        throw CloudAIError.apiError(statusCode: 0, message: "Apple PCC uses Shortcuts for processing")
    }
}
