//
//  GeminiClient.swift
//  PodcastAnalyzer
//
//  AI provider client for Google Gemini API.
//

import Foundation

nonisolated struct GeminiClient: AIProviderClient {
    let provider: CloudAIProvider
    let requiresAPIKey: Bool = true

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    // MARK: - Fetch Models

    func fetchAvailableModels(apiKey: String) async throws -> [String] {
        AIProviderHelpers.presentable(try await fetchModelListings(apiKey: apiKey))
    }

    /// `GET /v1beta/models`, following `nextPageToken` — the default page is 50
    /// and Google's catalogue is longer, so one request drops models.
    ///
    /// The key travels in `x-goog-api-key`, not `?key=`. Building the URL by
    /// interpolating the key and force-unwrapping crashed the app outright if
    /// the pasted key held a space or newline, and put the secret into every URL
    /// that gets logged along the way.
    private func fetchModelListings(apiKey: String) async throws -> [AIModelListing] {
        var listings: [AIModelListing] = []
        var pageToken: String?

        for _ in 0..<20 {
            guard var components = URLComponents(string: baseURL) else {
                throw CloudAIError.invalidResponse
            }
            var items = [URLQueryItem(name: "pageSize", value: "200")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = items
            guard let url = components.url else { throw CloudAIError.invalidResponse }

            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

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
            guard let page = json?["models"] as? [[String: Any]] else {
                throw CloudAIError.invalidResponse
            }

            listings += page.compactMap { model -> AIModelListing? in
                // Only models that can answer a chat request — the list also
                // carries embedding and tuning-only entries.
                guard let name = model["name"] as? String,
                      let methods = model["supportedGenerationMethods"] as? [String],
                      methods.contains("generateContent") else { return nil }
                return AIModelListing(id: name.replacingOccurrences(of: "models/", with: ""))
            }

            guard let next = json?["nextPageToken"] as? String, !next.isEmpty else { break }
            pageToken = next
        }

        return listings
    }

    // MARK: - Ping

    /// Auth check via the model list — no hardcoded model id to go stale, and
    /// no generation billed for a connection test.
    func ping(apiKey: String) async throws {
        _ = try await fetchModelListings(apiKey: apiKey)
    }

    // MARK: - Endpoints

    /// `…/models/{model}:{method}` with the key kept out of the URL.
    ///
    /// Throws rather than force-unwrapping: the model id reaches here from a
    /// text field on the local-server path, and `URL(string:)!` on a value with
    /// a stray space is a crash, not an error message.
    private func generateEndpoint(model: String, method: String, sse: Bool = false) throws -> URL {
        let path = "\(baseURL)/\(model):\(method)"
        guard var components = URLComponents(string: path) else {
            throw CloudAIError.invalidResponse
        }
        if sse { components.queryItems = [URLQueryItem(name: "alt", value: "sse")] }
        guard let url = components.url else { throw CloudAIError.invalidResponse }
        return url
    }

    // MARK: - Send Request

    func sendRequest(
        prompt: String,
        systemPrompt: String,
        apiKey: String,
        model: String,
        maxTokens: Int
    ) async throws -> String {
        let endpoint = try generateEndpoint(model: model, method: "generateContent")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "\(systemPrompt)\n\n\(prompt)"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": maxTokens
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
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let firstPart = parts.first,
              let text = firstPart["text"] as? String else {
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
        let endpoint = try generateEndpoint(model: model, method: "streamGenerateContent", sse: true)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "\(systemPrompt)\n\n\(prompt)"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": maxTokens
            ]
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
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorMessage.isEmpty ? "Gemini request failed" : errorMessage)
        }

        var fullContent = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }

            let jsonString = String(line.dropFirst(6))
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Gemini can emit a safety block or quota error as a single
            // streamed event with no candidate content. Without this check the
            // loop silently completes and the caller treats it as ".completed".
            if let message = AIProviderHelpers.extractStreamError(from: json) {
                throw CloudAIError.apiError(statusCode: 200, message: message)
            }

            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                continue
            }

            fullContent += text
            await MainActor.run { onChunk(fullContent) }
        }

        if fullContent.isEmpty {
            throw CloudAIError.apiError(
                statusCode: 200,
                message: "Gemini returned an empty response. The prompt may exceed the model's context window or was blocked by a safety filter — try a shorter episode or a different model."
            )
        }

        return fullContent
    }
}
