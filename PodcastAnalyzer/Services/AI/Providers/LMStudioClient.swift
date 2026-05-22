//
//  LMStudioClient.swift
//  PodcastAnalyzer
//
//  AI provider client for LM Studio. Uses LM Studio's native v1 REST API
//  (/api/v1/models) for the model listing — which returns every installed
//  LLM, not just the currently loaded ones — and falls back to the
//  OpenAI-compatible /v1/models endpoint when the native endpoint is
//  unavailable (older LM Studio versions). Chat completions still go through
//  /v1/chat/completions via OpenAICompatibleClient, since that path supports
//  streaming SSE and JIT model loading.
//
//  Auth: optional Bearer token (LM Studio 0.4.0+ "Manage Tokens"). Pass an
//  empty apiKey to skip the Authorization header.
//

import Foundation

nonisolated struct LMStudioClient: AIProviderClient {
    let provider: CloudAIProvider
    let fallbackModels: [String] = []
    let defaultModel: String = ""
    let requiresAPIKey: Bool = false

    let baseURL: URL

    // MARK: - Fetch Models (native /api/v1/models with OpenAI-compatible fallback)

    func fetchAvailableModels(apiKey: String) async throws -> [String] {
        // Prefer LM Studio's native endpoint — it includes both loaded and
        // downloaded-but-unloaded models, and lets us filter out embedding
        // models that can't be used for chat.
        let nativeURL = baseURL.appendingPathComponent("api/v1/models")
        if let models = try? await fetchFromNativeModels(url: nativeURL, apiKey: apiKey),
           !models.isEmpty {
            return models
        }

        // Fallback: OpenAI-compatible /v1/models for older LM Studio builds.
        let v1ModelsURL = baseURL.appendingPathComponent("v1/models")
        return (try? await fetchFromV1Models(url: v1ModelsURL, apiKey: apiKey)) ?? []
    }

    private func fetchFromNativeModels(url: URL, apiKey: String) async throws -> [String] {
        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["models"] as? [[String: Any]] else {
            return []
        }

        // Keep only LLMs — embedding models can't service chat completions.
        // The `key` field is the identifier accepted by /v1/chat/completions.
        return models.compactMap { model in
            let type = model["type"] as? String ?? "llm"
            guard type == "llm" else { return nil }
            return model["key"] as? String
        }
    }

    private func fetchFromV1Models(url: URL, apiKey: String) async throws -> [String] {
        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

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

    // MARK: - Ping (server reachability via models endpoint)

    func ping(apiKey: String) async throws {
        let url = baseURL.appendingPathComponent("api/v1/models")
        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        // 200 = native endpoint OK. 401/403 = server up but token wrong/missing.
        // 404 = older LM Studio without /api/v1 — try OpenAI-compatible fallback.
        switch httpResponse.statusCode {
        case 200:
            return
        case 401, 403:
            throw CloudAIError.apiError(
                statusCode: httpResponse.statusCode,
                message: "LM Studio rejected the API token. Check Server Settings › Manage Tokens."
            )
        default:
            // Fallback to /v1/models for older LM Studio
            let v1URL = baseURL.appendingPathComponent("v1/models")
            var fallbackRequest = URLRequest(url: v1URL)
            if !apiKey.isEmpty {
                fallbackRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            let (_, fallbackResponse) = try await URLSession.shared.data(for: fallbackRequest)
            guard let fallbackHTTP = fallbackResponse as? HTTPURLResponse,
                  fallbackHTTP.statusCode == 200 else {
                throw CloudAIError.apiError(
                    statusCode: httpResponse.statusCode,
                    message: "Cannot reach LM Studio at \(baseURL.absoluteString). Is the server running?"
                )
            }
        }
    }

    // MARK: - Delegate chat to OpenAI-compatible client

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
            apiKey: apiKey, model: model, maxTokens: maxTokens,
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
            apiKey: apiKey, model: model, maxTokens: maxTokens,
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
            apiKey: apiKey, model: model, maxTokens: maxTokens,
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
            apiKey: apiKey, model: model, maxTokens: maxTokens,
            disableThinking: disableThinking, onChunk: onChunk
        )
    }
}
