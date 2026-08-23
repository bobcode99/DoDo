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

    /// Fetch the live model list from the provider API.
    ///
    /// There is deliberately no hardcoded fallback list. Every one this app
    /// shipped had rotted — a Haiku snapshot id that never existed, Groq models
    /// decommissioned a year earlier — and a stale id fails as a 404 at analysis
    /// time, long after the picker made it look like a valid choice. The
    /// provider's own catalogue is the only listing that stays true.
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

// MARK: - Model listings

/// One entry from a provider's model catalogue.
nonisolated struct AIModelListing: Sendable {
    let id: String
    /// When the provider published the model, where it says. Used only for
    /// ordering; providers that omit it sort after those that have it.
    let created: Date?

    init(id: String, created: Date? = nil) {
        self.id = id
        self.created = created
    }

    /// `created` as the Unix seconds most OpenAI-shaped APIs return.
    init(id: String, unixSeconds: Any?) {
        self.id = id
        if let seconds = unixSeconds as? TimeInterval, seconds > 0 {
            self.created = Date(timeIntervalSince1970: seconds)
        } else {
            self.created = nil
        }
    }

    /// `created` as the ISO-8601 timestamp Anthropic returns.
    init(id: String, iso8601: String?) {
        self.id = id
        self.created = iso8601.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

nonisolated extension AIProviderHelpers {
    /// Substrings that mark a model as something other than a chat model.
    ///
    /// Exclusion, not an allowlist. The allowlists this replaced (`gpt-4` or
    /// `gpt-3.5`; `llama`, `mixtral` or `gemma`) silently hid every model family
    /// released after they were written, so the picker aged into showing only
    /// retired ids. A rule phrased as "not an embedding model" keeps working
    /// when the provider ships something whose name nobody here predicted.
    private static let nonChatMarkers = [
        "embed", "whisper", "transcribe", "tts", "audio", "speech",
        "dall-e", "image", "imagen", "moderation", "guard", "safety",
        "rerank", "realtime", "computer-use", "aqa"
    ]

    /// Chat-capable models, newest first.
    ///
    /// Ordering is by the provider's own publish date where it reports one, so
    /// "newest" needs no table of which release came after which — the answer
    /// arrives with the list. Undated entries (Gemini, LM Studio) fall back to
    /// reverse-alphabetical, which at least groups families together.
    static func presentable(_ listings: [AIModelListing]) -> [String] {
        let chat = listings.filter { listing in
            let id = listing.id.lowercased()
            return !nonChatMarkers.contains { id.contains($0) }
        }
        let dated = chat.filter { $0.created != nil }
            .sorted { $0.created! > $1.created! }
        let undated = chat.filter { $0.created == nil }
            .sorted { $0.id > $1.id }
        return (dated + undated).map(\.id)
    }
}
