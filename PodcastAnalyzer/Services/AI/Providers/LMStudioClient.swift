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
    let requiresAPIKey: Bool = false

    let baseURL: URL

    // MARK: - Fetch Models (native /api/v1/models with OpenAI-compatible fallback)

    func fetchAvailableModels(apiKey: String) async throws -> [String] {
        // Prefer LM Studio's native endpoint — it includes both loaded and
        // downloaded-but-unloaded models, and reports each model's type so
        // embedding models can be dropped.
        do {
            let models = try await fetchFromNativeModels(apiKey: apiKey)
            if !models.isEmpty { return AIProviderHelpers.presentable(models) }
        } catch {
            // Only fall through when the server answered and the answer was
            // unusable. If nothing is listening, the fallback request pays the
            // same connect timeout over again — that second wait is why a
            // typo'd address used to spin for two minutes instead of ten
            // seconds.
            if AIProbe.isUnreachable(error) { throw error }
        }

        // Older LM Studio builds predate /api/v1 and only serve the
        // OpenAI-compatible route.
        return AIProviderHelpers.presentable(try await fetchFromV1Models(apiKey: apiKey))
    }

    private func fetchFromNativeModels(apiKey: String) async throws -> [AIModelListing] {
        let url = baseURL.appendingPathComponent("api/v1/models")
        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await AIProbe.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw CloudAIError.apiError(
                statusCode: httpResponse.statusCode,
                message: "LM Studio returned HTTP \(httpResponse.statusCode) from /api/v1/models."
            )
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["models"] as? [[String: Any]] else {
            throw CloudAIError.invalidResponse
        }

        // Keep only LLMs — embedding models can't service chat completions.
        // The `key` field is the identifier accepted by /v1/chat/completions.
        return models.compactMap { model in
            let type = model["type"] as? String ?? "llm"
            guard type == "llm", let key = model["key"] as? String else { return nil }
            return AIModelListing(id: key)
        }
    }

    private func fetchFromV1Models(apiKey: String) async throws -> [AIModelListing] {
        let url = baseURL.appendingPathComponent("v1/models")
        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await AIProbe.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw CloudAIError.apiError(
                statusCode: httpResponse.statusCode,
                message: "Cannot reach LM Studio at \(baseURL.absoluteString). Is the server running?"
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

    // MARK: - Ping (server reachability via models endpoint)

    func ping(apiKey: String) async throws {
        let url = baseURL.appendingPathComponent("api/v1/models")
        var request = URLRequest(url: url)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await AIProbe.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        // 200 = native endpoint OK. 401/403 = server up but token wrong/missing.
        // Anything else = possibly an older LM Studio without /api/v1, so try
        // the OpenAI-compatible route. The server demonstrably answered by this
        // point, so the second request cannot become a second connect timeout.
        switch httpResponse.statusCode {
        case 200:
            return
        case 401, 403:
            throw CloudAIError.apiError(
                statusCode: httpResponse.statusCode,
                message: "LM Studio rejected the API token. Check Server Settings › Manage Tokens."
            )
        default:
            _ = try await fetchFromV1Models(apiKey: apiKey)
        }
    }

    // MARK: - Delegate chat to OpenAI-compatible client

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
