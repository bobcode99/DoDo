//
//  OllamaClient.swift
//  PodcastAnalyzer
//
//  AI provider client for Ollama. Uses OpenAI-compatible chat/streaming,
//  with a custom model fetch that supports both /v1/models and /api/tags.
//

import Foundation

nonisolated struct OllamaClient: AIProviderClient {
    let provider: CloudAIProvider
    let requiresAPIKey: Bool = false

    let baseURL: URL

    // MARK: - Fetch Models (Ollama-specific: /v1/models + /api/tags fallback)

    func fetchAvailableModels(apiKey: String) async throws -> [String] {
        do {
            let models = try await fetchFromV1Models()
            if !models.isEmpty { return AIProviderHelpers.presentable(models) }
        } catch {
            // Nothing listening means the /api/tags fallback would burn the
            // same connect timeout for the same answer. Fail once.
            if AIProbe.isUnreachable(error) { throw error }
        }

        return AIProviderHelpers.presentable(try await fetchFromAPITags())
    }

    private func fetchFromV1Models() async throws -> [AIModelListing] {
        let url = baseURL.appendingPathComponent("v1/models")
        let (data, response) = try await AIProbe.session.data(for: URLRequest(url: url))

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw CloudAIError.apiError(
                statusCode: httpResponse.statusCode,
                message: "Ollama returned HTTP \(httpResponse.statusCode) from /v1/models."
            )
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["data"] as? [[String: Any]] else {
            throw CloudAIError.invalidResponse
        }

        return models.compactMap { model in
            guard let id = model["id"] as? String else { return nil }
            return AIModelListing(id: id, unixSeconds: model["created"])
        }
    }

    private func fetchFromAPITags() async throws -> [AIModelListing] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, response) = try await AIProbe.session.data(for: URLRequest(url: url))

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw CloudAIError.apiError(
                statusCode: httpResponse.statusCode,
                message: "Cannot reach Ollama at \(baseURL.absoluteString). Is Ollama running?"
            )
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["models"] as? [[String: Any]] else {
            throw CloudAIError.invalidResponse
        }

        // `modified_at` is when the blob was pulled, which is the closest thing
        // Ollama offers to a release date and orders "what I installed lately"
        // the way a user expects.
        return models.compactMap { model in
            guard let name = model["name"] as? String else { return nil }
            return AIModelListing(id: name, iso8601: model["modified_at"] as? String)
        }
    }

    // MARK: - Ping (check /api/tags reachability)

    func ping(apiKey: String) async throws {
        _ = try await fetchFromAPITags()
    }

    // MARK: - Delegate send/stream to OpenAI-compatible client

    private var openAIClient: OpenAICompatibleClient {
        OpenAICompatibleClient(
            provider: provider,
            baseURL: baseURL.appendingPathComponent("v1/chat/completions"),
            requiresAPIKey: false
        )
    }

    func sendRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int
    ) async throws -> String {
        try await openAIClient.sendRequest(
            prompt: prompt, systemPrompt: systemPrompt,
            apiKey: "", model: model, maxTokens: maxTokens,
            disableThinking: false
        )
    }

    func sendRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int,
        disableThinking: Bool
    ) async throws -> String {
        try await openAIClient.sendRequest(
            prompt: prompt, systemPrompt: systemPrompt,
            apiKey: "", model: model, maxTokens: maxTokens,
            disableThinking: disableThinking
        )
    }

    func sendStreamingRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await openAIClient.sendStreamingRequest(
            prompt: prompt, systemPrompt: systemPrompt,
            apiKey: "", model: model, maxTokens: maxTokens,
            disableThinking: false, onChunk: onChunk
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
        try await openAIClient.sendStreamingRequest(
            prompt: prompt, systemPrompt: systemPrompt,
            apiKey: "", model: model, maxTokens: maxTokens,
            disableThinking: disableThinking, onChunk: onChunk
        )
    }
}
