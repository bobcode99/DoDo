//
//  AIProviderClient.swift
//  PodcastAnalyzer
//
//  Protocol that encapsulates all provider-specific behavior for AI backends.
//

import Foundation

/// Protocol for AI provider clients. Implementations are value-type structs (Sendable, nonisolated).
nonisolated protocol AIProviderClient: Sendable {

    /// The provider this client handles
    var provider: CloudAIProvider { get }

    /// Whether this provider requires an API key
    var requiresAPIKey: Bool { get }

    /// Statically known models shown when the API is unreachable
    var fallbackModels: [String] { get }

    /// Default model to select on first launch
    var defaultModel: String { get }

    /// Fetch live model list from the provider API
    func fetchAvailableModels(apiKey: String) async throws -> [String]

    /// Minimal round-trip to verify the key and endpoint are working
    func ping(apiKey: String) async throws

    /// Non-streaming completion
    func sendRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int
    ) async throws -> String

    /// Streaming completion; calls `onChunk` with the cumulative content string
    func sendStreamingRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String

    /// Non-streaming completion with optional thinking/reasoning disabled
    func sendRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int,
        disableThinking: Bool
    ) async throws -> String

    /// Streaming completion with optional thinking/reasoning disabled
    func sendStreamingRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int,
        disableThinking: Bool,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String
}

// MARK: - Default Implementations

extension AIProviderClient {
    var requiresAPIKey: Bool { true }

    func sendRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int,
        disableThinking: Bool
    ) async throws -> String {
        try await sendRequest(
            prompt: prompt, systemPrompt: systemPrompt,
            apiKey: apiKey, model: model, maxTokens: maxTokens
        )
    }

    func sendStreamingRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int,
        disableThinking: Bool,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await sendStreamingRequest(
            prompt: prompt, systemPrompt: systemPrompt,
            apiKey: apiKey, model: model, maxTokens: maxTokens,
            onChunk: onChunk
        )
    }
}

// MARK: - Shared Helpers

/// Shared helpers for reading error responses from streaming byte sequences
nonisolated enum AIProviderHelpers {
    /// Read error body from a byte stream (up to 500 chars)
    static func readStreamError(from bytes: URLSession.AsyncBytes) async throws -> String {
        var errorMessage = ""
        for try await line in bytes.lines {
            errorMessage += line
            if errorMessage.count > 500 { break }
        }
        return errorMessage
    }

    /// Parse a standard error JSON response (works for OpenAI, Claude, Gemini patterns)
    static func parseErrorMessage(from text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return nil
        }
        return message
    }

    /// Inspect a parsed SSE `data:` JSON payload for an error envelope. Returns the
    /// human-readable message when the event represents a failure, otherwise `nil`.
    ///
    /// Handles the shapes we see in practice:
    /// - LM Studio / OpenAI-compatible:   `{"error": "..."}`  or  `{"error": {"message": "..."}}`
    /// - Claude:                          `{"type": "error", "error": {"message": "..."}}`
    /// - Gemini:                          `{"error": {"message": "..."}}`
    ///                                    `{"promptFeedback": {"blockReason": "..."}}`
    /// - Ollama native:                   `{"error": "..."}`
    static func extractStreamError(from json: [String: Any]) -> String? {
        if let message = (json["error"] as? [String: Any])?["message"] as? String {
            return message
        }
        if let errorString = json["error"] as? String, !errorString.isEmpty {
            return errorString
        }
        if (json["type"] as? String) == "error" {
            return (json["error"] as? [String: Any])?["message"] as? String ?? "Stream error"
        }
        if let feedback = json["promptFeedback"] as? [String: Any],
           let reason = feedback["blockReason"] as? String {
            return "Request blocked: \(reason)"
        }
        return nil
    }
}
