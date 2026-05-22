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
    let fallbackModels: [String] = []
    let defaultModel: String = ""
    let requiresAPIKey: Bool = false

    let baseURL: URL

    // MARK: - Fetch Models (Ollama-specific: /v1/models + /api/tags fallback)

    func fetchAvailableModels(apiKey: String) async throws -> [String] {
        // Try OpenAI-compatible /v1/models first
        let v1ModelsURL = baseURL.appendingPathComponent("v1/models")
        if let models = try? await fetchFromV1Models(url: v1ModelsURL), !models.isEmpty {
            return models
        }

        // Fallback to Ollama native /api/tags
        let tagsURL = baseURL.appendingPathComponent("api/tags")
        return try await fetchFromAPITags(url: tagsURL)
    }

    private func fetchFromV1Models(url: URL) async throws -> [String] {
        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["data"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { $0["id"] as? String }
    }

    private func fetchFromAPITags(url: URL) async throws -> [String] {
        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["models"] as? [[String: Any]] else {
            return []
        }

        return models.compactMap { $0["name"] as? String }
    }

    // MARK: - Ping (check /api/tags reachability)

    func ping(apiKey: String) async throws {
        let tagsURL = baseURL.appendingPathComponent("api/tags")
        let request = URLRequest(url: tagsURL)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            throw CloudAIError.apiError(
                statusCode: httpResponse.statusCode,
                message: "Cannot reach Ollama at \(baseURL.absoluteString). Is Ollama running?"
            )
        }
    }

    // MARK: - Delegate send/stream to OpenAI-compatible client

    private var openAIClient: OpenAICompatibleClient {
        OpenAICompatibleClient(
            provider: provider,
            baseURL: baseURL.appendingPathComponent("v1/chat/completions"),
            fallbackModels: [],
            defaultModel: "",
            requiresAPIKey: false,
            pingModel: "",
            modelFilter: nil,
            modelSorter: nil,
            modelLimit: nil
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
