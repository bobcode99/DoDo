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

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let modelsEndpoint = URL(string: "https://api.anthropic.com/v1/models")!
    private let anthropicVersion = "2023-06-01"

    // MARK: - Fetch Models

    func fetchAvailableModels(apiKey: String) async throws -> [String] {
        AIProviderHelpers.presentable(try await fetchModelListings(apiKey: apiKey))
    }

    /// `GET /v1/models`, paginated 20 at a time — Anthropic's default page size
    /// is smaller than the catalogue, so a single request silently truncates it.
    /// `has_more` / `last_id` are followed to the end.
    private func fetchModelListings(apiKey: String) async throws -> [AIModelListing] {
        var listings: [AIModelListing] = []
        var afterID: String?

        // Bounded so a provider bug can't spin here forever; 20 pages is far
        // more catalogue than Anthropic has ever published.
        for _ in 0..<20 {
            var components = URLComponents(url: modelsEndpoint, resolvingAgainstBaseURL: false)!
            var items = [URLQueryItem(name: "limit", value: "100")]
            if let afterID { items.append(URLQueryItem(name: "after_id", value: afterID)) }
            components.queryItems = items

            var request = URLRequest(url: components.url!)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

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
            guard let page = json?["data"] as? [[String: Any]] else {
                throw CloudAIError.invalidResponse
            }

            listings += page.compactMap { model in
                guard let id = model["id"] as? String else { return nil }
                return AIModelListing(id: id, iso8601: model["created_at"] as? String)
            }

            guard json?["has_more"] as? Bool == true,
                  let lastID = json?["last_id"] as? String else { break }
            afterID = lastID
        }

        return listings
    }

    // MARK: - Ping

    /// Auth check via `GET /v1/models`.
    ///
    /// Previously a one-token completion against a hardcoded
    /// `claude-haiku-4-5-20251015` — an id that does not exist (the real Haiku
    /// 4.5 snapshot is `-20251001`), so Test Connection returned a 404 for every
    /// valid key. Asking for the catalogue needs no id to be right.
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
