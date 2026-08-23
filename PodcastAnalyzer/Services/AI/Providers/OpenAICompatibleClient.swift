//
//  OpenAICompatibleClient.swift
//  PodcastAnalyzer
//
//  Handles OpenAI, Groq, Grok, LMStudio, and Ollama — all share the OpenAI chat completions API format.
//

import Foundation

nonisolated struct OpenAICompatibleClient: AIProviderClient {
    let provider: CloudAIProvider
    let baseURL: URL
    let requiresAPIKey: Bool

    // MARK: - Fetch Models

    func fetchAvailableModels(apiKey: String) async throws -> [String] {
        let listings = try await fetchModelListings(apiKey: apiKey)
        return AIProviderHelpers.presentable(listings)
    }

    /// `GET /v1/models`. Unlike the chat endpoints this uses `AIProbe.session`,
    /// so a wrong host fails in seconds rather than sitting on the 60s default.
    private func fetchModelListings(apiKey: String) async throws -> [AIModelListing] {
        let modelsURL = baseURL.deletingLastPathComponent().appendingPathComponent("models")

        var request = URLRequest(url: modelsURL)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await AIProbe.session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CloudAIError.apiError(
                statusCode: httpResponse.statusCode,
                message: AIProviderHelpers.parseErrorMessage(from: body) ?? body
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

    // MARK: - Ping

    /// Reachability and auth in one call, via the model list.
    ///
    /// This used to POST a one-token completion to a hardcoded `pingModel`
    /// ("gpt-4o-mini", "grok-2-1212", …). When such an id is retired the test
    /// reports a broken connection for a perfectly good key, which is the
    /// opposite of what a connection test is for. `/models` needs no id at all,
    /// still 401s on a bad key, and costs nothing.
    func ping(apiKey: String) async throws {
        _ = try await fetchModelListings(apiKey: apiKey)
    }

    // MARK: - Send Request

    func sendRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int
    ) async throws -> String {
        try await sendRequest(
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
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": maxTokens
        ]
        if disableThinking { body["think"] = false }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // Some local servers (notably LM Studio) report failures with HTTP 200 +
        // an `error` field instead of a 4xx — surface that to the user rather
        // than masquerading as `invalidResponse`.
        if let json, let message = AIProviderHelpers.extractStreamError(from: json) {
            throw CloudAIError.apiError(statusCode: 200, message: message)
        }
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw CloudAIError.invalidResponse
        }

        return content
    }

    // MARK: - Streaming Request

    func sendStreamingRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await sendStreamingRequest(
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
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": maxTokens,
            "stream": true
        ]
        if disableThinking { body["think"] = false }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMessage = try await AIProviderHelpers.readStreamError(from: bytes)
            if let parsed = AIProviderHelpers.parseErrorMessage(from: errorMessage) {
                throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: parsed)
            }
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage.isEmpty ? "Request failed" : errorMessage)
        }

        var fullContent = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }

            let jsonString = String(line.dropFirst(6))
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // LM Studio surfaces context-length and load-time failures as a 200
            // response that emits a single `data: {"error": "..."}` SSE event
            // and closes the stream. Without this check the loop just falls
            // through and we return an empty `fullContent`, which the caller
            // happily reports as ".completed". Surface it as an apiError so
            // the UI shows the actual reason.
            if let message = AIProviderHelpers.extractStreamError(from: json) {
                throw CloudAIError.apiError(statusCode: 200, message: message)
            }

            guard let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }

            fullContent += content
            await MainActor.run { onChunk(fullContent) }
        }

        if fullContent.isEmpty {
            throw CloudAIError.apiError(
                statusCode: 200,
                message: "\(provider.displayName) returned an empty response. The prompt may exceed the model's context window — try a shorter episode or a model with a larger context."
            )
        }

        return fullContent
    }
}

// MARK: - Factory Methods (values inlined to avoid @MainActor isolation issues)

extension OpenAICompatibleClient {
    static func openAI() -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            provider: .openai,
            baseURL: URL(string: "https://api.openai.com/v1/chat/completions")!,
            requiresAPIKey: true
        )
    }

    static func groq() -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            provider: .groq,
            baseURL: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            requiresAPIKey: true
        )
    }

    static func grok() -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            provider: .grok,
            baseURL: URL(string: "https://api.x.ai/v1/chat/completions")!,
            requiresAPIKey: true
        )
    }

    /// LM Studio's OpenAI-compatible endpoint. Auth is optional: when the user
    /// has not enabled "Manage Tokens" in LM Studio, pass an empty apiKey and
    /// the client skips the Authorization header.
    static func lmStudio(baseURL: URL) -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            provider: .lmstudio,
            baseURL: baseURL.appendingPathComponent("v1/chat/completions"),
            requiresAPIKey: false
        )
    }
}
