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
    let fallbackModels: [String]
    let defaultModel: String
    let requiresAPIKey: Bool
    /// Cheapest model to use for ping (connection test)
    let pingModel: String
    /// Custom model filter for fetchAvailableModels (nil = return all models)
    let modelFilter: (@Sendable (String) -> Bool)?
    /// Custom model sorter for fetchAvailableModels
    let modelSorter: (@Sendable (String, String) -> Bool)?
    /// Max fetched models to surface (nil = no limit). Cloud providers cap at 10
    /// so their large catalogs stay manageable; local servers default to nil so
    /// the user actually sees every model they have available.
    let modelLimit: Int?

    // MARK: - Fetch Models

    func fetchAvailableModels(apiKey: String) async throws -> [String] {
        let modelsURL = baseURL.deletingLastPathComponent().appendingPathComponent("models")

        var request = URLRequest(url: modelsURL)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return fallbackModels
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let models = json?["data"] as? [[String: Any]] else {
            return fallbackModels
        }

        var modelIds = models.compactMap { $0["id"] as? String }

        if let filter = modelFilter {
            modelIds = modelIds.filter(filter)
        }

        if let sorter = modelSorter {
            modelIds.sort(by: sorter)
        }

        if modelIds.isEmpty { return fallbackModels }
        if let limit = modelLimit { return Array(modelIds.prefix(limit)) }
        return modelIds
    }

    // MARK: - Ping

    func ping(apiKey: String) async throws {
        // Local servers without a default pingModel (e.g. LM Studio) verify
        // reachability via /v1/models instead — sending a chat request with
        // an empty model name fails before we ever reach the server.
        if pingModel.isEmpty {
            try await pingViaModelsList(apiKey: apiKey)
            return
        }

        let chatURL = baseURL
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": pingModel,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1
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
        guard json?["choices"] != nil else {
            throw CloudAIError.invalidResponse
        }
    }

    private func pingViaModelsList(apiKey: String) async throws {
        let modelsURL = baseURL.deletingLastPathComponent().appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw CloudAIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
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
            fallbackModels: CloudAIProvider.openai.availableModels,
            defaultModel: CloudAIProvider.openai.defaultModel,
            requiresAPIKey: true,
            pingModel: "gpt-4o-mini",
            modelFilter: { id in
                (id.contains("gpt-4") || id.contains("gpt-3.5"))
                && !id.contains("instruct") && !id.contains("vision") && !id.contains("realtime")
            },
            modelSorter: { a, b in
                if a.contains("4.1") && !b.contains("4.1") { return true }
                if !a.contains("4.1") && b.contains("4.1") { return false }
                if a.contains("4o") && !b.contains("4o") { return true }
                if !a.contains("4o") && b.contains("4o") { return false }
                return a < b
            },
            modelLimit: 10
        )
    }

    static func groq() -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            provider: .groq,
            baseURL: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            fallbackModels: CloudAIProvider.groq.availableModels,
            defaultModel: CloudAIProvider.groq.defaultModel,
            requiresAPIKey: true,
            pingModel: "llama-3.1-8b-instant",
            modelFilter: { id in
                (id.contains("llama") || id.contains("mixtral") || id.contains("gemma"))
                && !id.contains("guard")
            },
            modelSorter: { a, b in
                if a.contains("70b") && !b.contains("70b") { return true }
                if !a.contains("70b") && b.contains("70b") { return false }
                if a.contains("90b") && !b.contains("90b") { return true }
                if !a.contains("90b") && b.contains("90b") { return false }
                return a > b
            },
            modelLimit: 10
        )
    }

    static func grok() -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            provider: .grok,
            baseURL: URL(string: "https://api.x.ai/v1/chat/completions")!,
            fallbackModels: CloudAIProvider.grok.availableModels,
            defaultModel: CloudAIProvider.grok.defaultModel,
            requiresAPIKey: true,
            pingModel: "grok-2-1212",
            modelFilter: { id in
                id.contains("grok") && !id.contains("vision") && !id.contains("image")
            },
            modelSorter: { a, b in
                if a.contains("4") && !b.contains("4") { return true }
                if !a.contains("4") && b.contains("4") { return false }
                if a.contains("3") && !b.contains("3") { return true }
                if !a.contains("3") && b.contains("3") { return false }
                return a > b
            },
            modelLimit: 10
        )
    }

    /// LM Studio's OpenAI-compatible endpoint. Auth is optional: when the user
    /// has not enabled "Manage Tokens" in LM Studio, pass an empty apiKey and
    /// the client skips the Authorization header. modelLimit is nil so users
    /// see every model installed locally (cloud providers cap at 10 to hide
    /// large catalogs, but LM Studio users explicitly chose what to install).
    static func lmStudio(baseURL: URL) -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            provider: .lmstudio,
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
}
