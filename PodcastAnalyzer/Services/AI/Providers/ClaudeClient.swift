//
//  ClaudeClient.swift
//  PodcastAnalyzer
//
//  AI provider client for Claude (Anthropic) API.
//

import Foundation

nonisolated struct ClaudeClient: AIProviderClient {
    let provider: CloudAIProvider
    let requiresAPIKey: Bool = true
    let fallbackModels: [String]
    let defaultModel: String

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let modelsEndpoint = URL(string: "https://api.anthropic.com/v1/models")!
    private let anthropicVersion = "2023-06-01"
    private let pingModel = "claude-haiku-4-5-20251015"

    // MARK: - Fetch Models

    func fetchAvailableModels(apiKey: String) async throws -> [String] {
        var request = URLRequest(url: modelsEndpoint)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return fallbackModels
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["data"] as? [[String: Any]] else {
            return fallbackModels
        }

        let modelIds = models.compactMap { $0["id"] as? String }
            .filter { id in
                id.contains("claude-3") || id.contains("claude-4")
                || id.contains("claude-sonnet") || id.contains("claude-opus") || id.contains("claude-haiku")
            }
            .sorted { a, b in
                if a.contains("4") && !b.contains("4") { return true }
                if !a.contains("4") && b.contains("4") { return false }
                if a.contains("opus") && !b.contains("opus") { return true }
                if !a.contains("opus") && b.contains("opus") { return false }
                if a.contains("sonnet") && !b.contains("sonnet") { return true }
                return a > b
            }

        return modelIds.isEmpty ? fallbackModels : Array(modelIds.prefix(8))
    }

    // MARK: - Ping

    func ping(apiKey: String) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": pingModel,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ]

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
        guard json?["content"] != nil else {
            throw CloudAIError.invalidResponse
        }
    }

    // MARK: - Send Request

    func sendRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

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
        guard let content = json?["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw CloudAIError.invalidResponse
        }

        return text
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
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "stream": true
        ]

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
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage.isEmpty ? "Claude request failed" : errorMessage)
        }

        var fullContent = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }

            let jsonString = String(line.dropFirst(6))
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Claude sends explicit `event: error` SSE frames mid-stream (e.g.,
            // overloaded_error). Surface them instead of silently dropping the
            // event and returning an empty response.
            if let message = AIProviderHelpers.extractStreamError(from: json) {
                throw CloudAIError.apiError(statusCode: 200, message: message)
            }

            if let type = json["type"] as? String,
               type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                fullContent += text
                await MainActor.run { onChunk(fullContent) }
            }
        }

        if fullContent.isEmpty {
            throw CloudAIError.apiError(
                statusCode: 200,
                message: "Claude returned an empty response. The prompt may exceed the model's context window — try a shorter episode or a model with a larger context."
            )
        }

        return fullContent
    }
}
