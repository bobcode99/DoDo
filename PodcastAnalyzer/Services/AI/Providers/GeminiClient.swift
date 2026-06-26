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
    let fallbackModels: [String]
    let defaultModel: String

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"
    private let pingModel = "gemini-2.0-flash"

    // MARK: - Fetch Models

    func fetchAvailableModels(apiKey: String) async throws -> [String] {
        let endpoint = URL(string: "\(baseURL)?key=\(apiKey)")!
        let request = URLRequest(url: endpoint)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudAIError.invalidResponse
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["models"] as? [[String: Any]] else {
            throw CloudAIError.invalidResponse
        }

        let geminiModels = models.compactMap { model -> String? in
            guard let name = model["name"] as? String,
                  let supportedMethods = model["supportedGenerationMethods"] as? [String],
                  supportedMethods.contains("generateContent") else {
                return nil
            }
            return name.replacingOccurrences(of: "models/", with: "")
        }
        .filter { id in
            id.contains("gemini") && !id.contains("embedding") && !id.contains("aqa")
        }
        .sorted { a, b in
            if a.contains("2.5") && !b.contains("2.5") { return true }
            if !a.contains("2.5") && b.contains("2.5") { return false }
            if a.contains("2.0") && !b.contains("2.0") { return true }
            if !a.contains("2.0") && b.contains("2.0") { return false }
            if a.contains("pro") && !b.contains("pro") { return true }
            if !a.contains("pro") && b.contains("pro") { return false }
            return a < b
        }

        return geminiModels.isEmpty ? fallbackModels : Array(geminiModels.prefix(10))
    }

    // MARK: - Ping

    func ping(apiKey: String) async throws {
        let endpoint = URL(string: "\(baseURL)/\(pingModel):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": "ping"]]]
            ],
            "generationConfig": [
                "maxOutputTokens": 1
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
        guard json?["candidates"] != nil else {
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
        let endpoint = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
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
        let endpoint = URL(string: "\(baseURL)/\(model):streamGenerateContent?key=\(apiKey)&alt=sse")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
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
