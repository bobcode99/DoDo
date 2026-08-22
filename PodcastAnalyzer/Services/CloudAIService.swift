//
//  CloudAIService.swift
//  PodcastAnalyzer
//
//  Service for cloud-based AI analysis using user-provided API keys (BYOK)
//  Supports OpenAI, Claude, Gemini, Groq, Grok, LMStudio, Ollama, and Shortcuts integration
//

import Foundation
import OSLog
#if os(iOS)
import UIKit
#endif
// MARK: - Cloud AI Service

@MainActor
final class CloudAIService {
    static let shared = CloudAIService()

    private let settings = AISettingsManager.shared
    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "CloudAIService")

    // MARK: - Provider Registry

    /// Cached clients for cloud providers (static endpoints)
    private let cloudClients: [CloudAIProvider: any AIProviderClient]

    private init() {
        var map: [CloudAIProvider: any AIProviderClient] = [:]
        map[.applePCC] = ShortcutsClient(
            provider: .applePCC,
            fallbackModels: ["Shortcuts"],
            defaultModel: "Shortcuts"
        )
        map[.openai] = OpenAICompatibleClient.openAI()
        map[.groq] = OpenAICompatibleClient.groq()
        map[.grok] = OpenAICompatibleClient.grok()
        map[.claude] = ClaudeClient(
            provider: .claude,
            fallbackModels: CloudAIProvider.claude.availableModels,
            defaultModel: CloudAIProvider.claude.defaultModel
        )
        map[.gemini] = GeminiClient(
            provider: .gemini,
            fallbackModels: CloudAIProvider.gemini.availableModels,
            defaultModel: CloudAIProvider.gemini.defaultModel
        )
        cloudClients = map
    }

    /// Returns the appropriate client for the given provider.
    /// Local providers (LMStudio, Ollama) are built fresh each time to pick up URL changes.
    private func client(for provider: CloudAIProvider) -> any AIProviderClient {
        switch provider {
        case .lmstudio:
            return LMStudioClient(provider: .lmstudio, baseURL: settings.lmstudioBaseURL)
        case .ollama:
            return OllamaClient(provider: .ollama, baseURL: settings.ollamaBaseURL)
        default:
            return cloudClients[provider]!
        }
    }

    // MARK: - Fetch Available Models

    func fetchAvailableModels(for provider: CloudAIProvider, apiKey: String) async throws -> [String] {
        try await client(for: provider).fetchAvailableModels(apiKey: apiKey)
    }

    // MARK: - Test Connection

    func testConnection() async throws -> Bool {
        let provider = settings.selectedProvider
        let apiKey = settings.currentAPIKey

        if provider == .applePCC {
            return true
        }

        if provider.requiresAPIKey {
            guard !apiKey.isEmpty else {
                throw CloudAIError.noAPIKey
            }
        }

        try await client(for: provider).ping(apiKey: apiKey)
        return true
    }

    // MARK: - Apple PCC via Shortcuts

    /// Analyze transcript using Shortcuts
    private func analyzeWithShortcuts(
        transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType,
        podcastLanguage: String? = nil,
        formatHint: String? = nil,
        speakerBlock: String = "",
        progressCallback: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> CloudAnalysisResult {
        progressCallback?("Starting Shortcuts analysis...", 0.2)

        // Log the language setting
        let languageInstruction = settings.analysisLanguage.getLanguageInstruction(podcastLanguage: podcastLanguage, customLanguageName: settings.customAnalysisLanguageName)
        logger.info("Shortcuts Analysis Request - Type: \(analysisType.rawValue), Language setting: \(self.settings.analysisLanguage.rawValue), Instruction: \(languageInstruction.isEmpty ? "None" : languageInstruction)")

        // Build the prompt with JSON format
        let prompt = buildShortcutsPrompt(
            transcript: transcript,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            analysisType: analysisType,
            podcastLanguage: podcastLanguage,
            formatHint: formatHint,
            speakerBlock: speakerBlock,
        )

        progressCallback?("Running shortcut...", 0.4)

        let shortcutsService = ShortcutsAIService.shared

        do {
            let rawResult = try await shortcutsService.runShortcut(input: prompt, timeout: settings.shortcutsTimeout * 1.5)

            progressCallback?("Formatting result...", 0.95)

            // Same tolerant path as the streaming providers: fence anywhere,
            // prose around the object, and an all-empty decode counts as a miss.
            var parsedAnalysis = Self.decodeJSON(rawResult, as: ParsedEpisodeAnalysisResponse.self)
            if parsedAnalysis?.isEmpty == true { parsedAnalysis = nil }
            let jsonParseWarning = parsedAnalysis == nil ? Self.unstructuredResponseWarning : nil

            // Format the raw response if JSON parsing failed
            let displayContent: String
            if jsonParseWarning != nil {
                displayContent = formatRawResponseForDisplay(rawResult)
            } else {
                displayContent = rawResult
            }

            return CloudAnalysisResult(
                type: analysisType,
                content: displayContent,
                parsedAnalysis: parsedAnalysis,
                provider: .applePCC,
                model: ShortcutsAIService.shared.shortcutName,
                timestamp: Date(),
                jsonParseWarning: jsonParseWarning
            )

        } catch let error as ShortcutsError {
            // Do NOT call progressCallback here — the outer catch in generateCloudAnalysis
            // sets cloudAnalysisState = .error(...) synchronously. If we dispatch a
            // progressCallback task first, it runs after the catch and overwrites .error
            // with .analyzing("Error"), hiding the error banner from the user.
            throw CloudAIError.apiError(statusCode: 0, message: error.localizedDescription)
        } catch {
            throw error
        }
    }

    /// Clean JSON response by removing markdown code blocks
    private func cleanJSONResponse(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove markdown code blocks
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }

        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Format raw response for human-readable display
    private func formatRawResponseForDisplay(_ response: String) -> String {
        // Try to pretty print if it's JSON
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }

        // Otherwise return as-is
        return response
    }

    /// Ask a question using Shortcuts
    private func askQuestionWithShortcuts(
        question: String,
        transcript: String,
        episodeTitle: String,
        podcastLanguage: String? = nil,
        progressCallback: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> CloudQAResult {
        progressCallback?("Preparing question for Shortcuts...", 0.2)

        let languageInstruction = settings.analysisLanguage.getLanguageInstruction(podcastLanguage: podcastLanguage, customLanguageName: settings.customAnalysisLanguageName)
        let languageLine = languageInstruction.isEmpty ? "" : "\n\nLanguage: \(languageInstruction)"

        // Log the language setting
        logger.info("Q&A Shortcuts Request - Language setting: \(self.settings.analysisLanguage.rawValue), Instruction: \(languageInstruction.isEmpty ? "None" : languageInstruction)")

        let prompt = """
        Based on this podcast transcript, please answer the following question.

        Episode: \(episodeTitle)

        Question: \(question)

        IMPORTANT: Return ONLY valid JSON with no additional text, markdown, or code blocks.

        Return JSON in this exact format:
        {
            "answer": "Your detailed answer to the question",
            "confidence": "high/medium/low based on how clearly the transcript addresses this",
            "relatedTopics": ["topic1", "topic2"] or null if none,
            "sources": ["Brief quote or reference from transcript"] or null if none
        }\(languageLine)

        Transcript:
        \(transcript)
        """

        progressCallback?("Running shortcut...", 0.4)

        let shortcutsService = ShortcutsAIService.shared

        do {
            let rawResult = try await shortcutsService.runShortcut(input: prompt, timeout: settings.shortcutsTimeout * 1.5)

            progressCallback?("Parsing response...", 0.8)

            // Clean and parse the JSON response
            let cleanedResult = cleanJSONResponse(rawResult)
            let parsed = parseJSON(cleanedResult, as: ParsedQAResponse.self)

            // Log the response
            logger.info("Q&A Shortcuts Response - Parsed successfully: \(parsed != nil)")

            var jsonParseWarning: String?
            if parsed == nil {
                jsonParseWarning = "JSON parsing failed - showing raw response"
                logger.warning("Q&A Shortcuts JSON parsing failed, falling back to raw response")
            }

            progressCallback?("Done", 1.0)

            return CloudQAResult(
                question: question,
                answer: parsed?.answer ?? formatRawResponseForDisplay(rawResult),
                confidence: parsed?.confidence ?? "unknown",
                relatedTopics: parsed?.relatedTopics,
                sources: parsed?.sources,
                provider: .applePCC,
                model: ShortcutsAIService.shared.shortcutName,
                timestamp: Date(),
                jsonParseWarning: jsonParseWarning
            )

        } catch let error as ShortcutsError {
            // Same race-condition fix as analyzeWithShortcuts — do not dispatch
            // a progressCallback here or it will overwrite the outer .error state.
            throw CloudAIError.apiError(statusCode: 0, message: error.localizedDescription)
        } catch {
            throw error
        }
    }

    /// Build a prompt for Shortcuts analysis - matches the JSON format used by other LLMs
    private func buildShortcutsPrompt(
        transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType,
        podcastLanguage: String? = nil,
        formatHint: String? = nil,
        speakerBlock: String = ""
    ) -> String {
        let languageInstruction = settings.analysisLanguage.getLanguageInstruction(podcastLanguage: podcastLanguage, customLanguageName: settings.customAnalysisLanguageName)
        let languageLine = languageInstruction.isEmpty ? "" : "\n\nLanguage: \(languageInstruction)"

        let formatHintLine: String
        if let hint = formatHint, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formatHintLine = "\n\nPodcast Format Context: \(hint)\nUse this to understand the episode structure and skip any sponsored/advertisement segments in your analysis."
        } else {
            formatHintLine = "\n\nNote: If the transcript contains sponsored or advertisement segments, ignore them — do not include ads in topics, takeaways, highlights, or quotes."
        }

        // Analyze always uses sentence-based transcripts — QuotesFinder
        // reattaches timestamps after parsing.
        let quotesSchema = #""notableQuotes": ["quote 1", "quote 2"]"#
        let quotesNote = ""
        return """
        You are an expert podcast analyst. Provide a single comprehensive analysis of this podcast episode.

        Podcast: \(podcastTitle)
        Episode: \(episodeTitle)

        IMPORTANT: Return ONLY valid JSON with no additional text, markdown, or code blocks.

        Return JSON in this exact format:
        {
            "overview": "2-3 paragraph executive summary of the episode",
            "mainTopics": [
                {
                    "topic": "Topic Name",
                    "summary": "Brief summary of this topic",
                    "keyPoints": ["point 1", "point 2"]
                }
            ],
            "keyTakeaways": ["takeaway 1", "takeaway 2", "takeaway 3"],
            "keyInsights": ["insight 1", "insight 2", "insight 3"],
            "targetAudience": "Description of who would benefit from this episode",
            "engagementLevel": "high/medium/low",
            "people": ["person1", "person2"],
            "organizations": ["org1", "org2"],
            "products": ["product1", "product2"],
            "locations": ["location1", "location2"],
            "resources": ["book1", "article1"],
            "highlights": ["highlight1", "highlight2", "highlight3"],
            \(quotesSchema),
            "actionItems": ["action1", "action2"],
            "controversialPoints": ["point1"] or null,
            "entertainingMoments": ["moment1"] or null,
            "qaHighlights": [{"question": "question text", "answer": "answer text"}] or null if no Q&A section exists,
            "conclusion": "Overall assessment and who would benefit from this episode"
        }\(quotesNote)\(formatHintLine)\(speakerBlock)\(languageLine)

        Transcript:
        \(transcript)
        """
    }

    // MARK: - Streaming Transcript Analysis

    /// Analyze transcript with streaming response.
    ///
    /// The analyze path always sends a sentence-based (timestamp-free)
    /// transcript to the model — timestamps are reattached post-hoc by
    /// `QuotesFinder` using `transcriptSegments`, which keeps prompt tokens
    /// down without losing the per-quote playback affordance. The user's
    /// saved `settings.transcriptFormat` is only honoured by the "Copy
    /// Prompt" preview path (`buildPrompt`).
    func analyzeTranscriptStreaming(
        _ transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType,
        podcastLanguage: String? = nil,
        formatHint: String? = nil,
        speakerBlock: String = "",
        transcriptSegments: [QuotesFinder.Segment] = [],
        onChunk: @escaping @Sendable (String) -> Void,
        progressCallback: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> CloudAnalysisResult {
        let provider = settings.selectedProvider
        let apiKey = settings.currentAPIKey
        let model = settings.currentModel

        // Always sentence-based for AI analysis to minimise prompt tokens.
        let analyzeFormat: TranscriptFormatForAI = .sentenceBased
        let formattedTranscript = analyzeFormat.formatTranscript(transcript)
        logger.info("Analyze using forced \(analyzeFormat.rawValue) format")

        // Handle Apple PCC via Shortcuts
        if provider == .applePCC {
            progressCallback?("Preparing for Shortcuts...", 0.2)
            let result = try await analyzeWithShortcuts(
                transcript: formattedTranscript,
                episodeTitle: episodeTitle,
                podcastTitle: podcastTitle,
                analysisType: analysisType,
                podcastLanguage: podcastLanguage,
                formatHint: formatHint,
                speakerBlock: speakerBlock,
                progressCallback: progressCallback
            )
            return Self.enrichQuotes(in: result, segments: transcriptSegments)
        }

        if provider.requiresAPIKey {
            guard !apiKey.isEmpty else {
                throw CloudAIError.noAPIKey
            }
        }

        progressCallback?("Preparing analysis...", 0.1)

        // Log the language setting for streaming analysis
        let languageInstruction = settings.analysisLanguage.getLanguageInstruction(podcastLanguage: podcastLanguage, customLanguageName: settings.customAnalysisLanguageName)
        logger.info("Streaming Analysis Request - Provider: \(provider.displayName), Type: \(analysisType.rawValue), Language setting: \(self.settings.analysisLanguage.rawValue), Instruction: \(languageInstruction.isEmpty ? "None" : languageInstruction)")

        let systemPrompt = buildSystemPrompt(
            for: analysisType,
            podcastLanguage: podcastLanguage,
            formatHint: formatHint,
            speakerBlock: speakerBlock,
            transcriptFormatOverride: analyzeFormat
        )
        let userPrompt = buildUserPrompt(
            transcript: formattedTranscript,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            analysisType: analysisType,
            formatHint: formatHint,
            speakerBlock: speakerBlock,
            transcriptFormatOverride: analyzeFormat
        )

        progressCallback?("Connecting to \(provider.displayName)...", 0.15)

        let maxTokens = 8192

        // Use streaming via the provider client
        let providerClient = client(for: provider)
        let fullResponse = try await providerClient.sendStreamingRequest(
            prompt: userPrompt,
            systemPrompt: systemPrompt,
            apiKey: apiKey,
            model: model,
            maxTokens: maxTokens,
            disableThinking: provider.usesLocalServer && settings.disableThinkingForLocalModels,
            onChunk: { text in
                onChunk(text)
                let estimatedProgress = min(0.85, 0.2 + Double(text.count) / 5000.0 * 0.65)
                progressCallback?("Generating response...", estimatedProgress)
            }
        )

        progressCallback?("Formatting result...", 0.95)

        // A decode that yields nothing renderable counts as a failure, so the
        // caller falls back to the raw text instead of showing an empty card.
        var parsedAnalysis = parseJSON(fullResponse, as: ParsedEpisodeAnalysisResponse.self)
        if parsedAnalysis?.isEmpty == true { parsedAnalysis = nil }

        if parsedAnalysis == nil {
            logger.error(
                "Analysis response did not decode - provider: \(provider.displayName, privacy: .public), chars: \(fullResponse.count)"
            )
        }

        let result = CloudAnalysisResult(
            type: analysisType,
            content: fullResponse,
            parsedAnalysis: parsedAnalysis,
            provider: provider,
            model: model,
            timestamp: Date(),
            jsonParseWarning: parsedAnalysis == nil ? Self.unstructuredResponseWarning : nil
        )
        return Self.enrichQuotes(in: result, segments: transcriptSegments)
    }

    // MARK: - Quote Enrichment

    /// Replace `parsedAnalysis.notableQuotes` with timestamp-enriched copies
    /// produced by `QuotesFinder`, leaving the rest of the result untouched.
    private static func enrichQuotes(
        in result: CloudAnalysisResult,
        segments: [QuotesFinder.Segment]
    ) -> CloudAnalysisResult {
        guard !segments.isEmpty,
              let parsed = result.parsedAnalysis,
              !parsed.notableQuotes.isEmpty else {
            return result
        }

        let enriched = QuotesFinder.enrich(quotes: parsed.notableQuotes, segments: segments)
        let updatedParsed = ParsedEpisodeAnalysisResponse(
            overview: parsed.overview,
            mainTopics: parsed.mainTopics,
            keyTakeaways: parsed.keyTakeaways,
            keyInsights: parsed.keyInsights,
            targetAudience: parsed.targetAudience,
            engagementLevel: parsed.engagementLevel,
            people: parsed.people,
            organizations: parsed.organizations,
            products: parsed.products,
            locations: parsed.locations,
            resources: parsed.resources,
            highlights: parsed.highlights,
            notableQuotes: enriched,
            actionItems: parsed.actionItems,
            controversialPoints: parsed.controversialPoints,
            entertainingMoments: parsed.entertainingMoments,
            qaHighlights: parsed.qaHighlights,
            conclusion: parsed.conclusion
        )
        return CloudAnalysisResult(
            type: result.type,
            content: result.content,
            parsedAnalysis: updatedParsed,
            provider: result.provider,
            model: result.model,
            timestamp: result.timestamp,
            jsonParseWarning: result.jsonParseWarning
        )
    }

    // MARK: - Transcript Analysis

    func analyzeTranscript(
        _ transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType,
        podcastLanguage: String? = nil,
        formatHint: String? = nil,
        speakerBlock: String = "",
        progressCallback: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> CloudAnalysisResult {
        let provider = settings.selectedProvider
        let apiKey = settings.currentAPIKey
        let model = settings.currentModel

        if provider.requiresAPIKey {
            guard !apiKey.isEmpty else {
                throw CloudAIError.noAPIKey
            }
        }

        progressCallback?("Preparing analysis...", 0.1)

        // Format transcript based on user's preference (segment-based vs sentence-based)
        let formattedTranscript = settings.transcriptFormat.formatTranscript(transcript)

        let systemPrompt = buildSystemPrompt(for: analysisType, podcastLanguage: podcastLanguage, formatHint: formatHint, speakerBlock: speakerBlock)
        let userPrompt = buildUserPrompt(
            transcript: formattedTranscript,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            analysisType: analysisType,
            formatHint: formatHint,
            speakerBlock: speakerBlock,
        )

        progressCallback?("Sending to \(provider.displayName)...", 0.3)

        let providerClient = client(for: provider)
        let response = try await providerClient.sendRequest(
            prompt: userPrompt,
            systemPrompt: systemPrompt,
            apiKey: apiKey,
            model: model,
            maxTokens: 8192,
            disableThinking: provider.usesLocalServer && settings.disableThinkingForLocalModels
        )

        progressCallback?("Parsing response...", 0.8)

        let parsedAnalysis = parseJSON(response, as: ParsedEpisodeAnalysisResponse.self)

        progressCallback?("Done", 1.0)

        return CloudAnalysisResult(
            type: analysisType,
            content: response,
            parsedAnalysis: parsedAnalysis,
            provider: provider,
            model: model,
            timestamp: Date()
        )
    }

    /// Shown when the model's answer arrived but could not be turned into
    /// sections — the text is still displayed verbatim.
    static let unstructuredResponseWarning =
        "The model's reply wasn't valid JSON, so it's shown as plain text. "
        + "This usually means the response was cut short — try Regenerate, or switch to a model with a larger output limit."

    /// Parse JSON from an AI response, tolerating the wrappers models add:
    /// a markdown fence (anywhere, not just at the start) and leading or
    /// trailing prose around the object.
    private func parseJSON<T: Decodable>(_ response: String, as type: T.Type) -> T? {
        guard let decoded = Self.decodeJSON(response, as: type) else {
            logger.error("JSON parsing failed for \(String(describing: type), privacy: .public)")
            return nil
        }
        return decoded
    }

    nonisolated static func decodeJSON<T: Decodable>(_ response: String, as type: T.Type) -> T? {
        for candidate in jsonCandidates(in: response) {
            guard let data = candidate.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(T.self, from: data) { return decoded }
        }
        return nil
    }

    /// Payloads worth attempting, cheapest and most-likely first.
    nonisolated private static func jsonCandidates(in response: String) -> [String] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates = [trimmed]
        if let fenced = fencedBlock(in: trimmed) { candidates.append(fenced) }
        if let object = balancedObject(in: trimmed) { candidates.append(object) }
        return candidates
    }

    /// Contents of the first ``` / ```json fence, if one is present.
    nonisolated private static func fencedBlock(in text: String) -> String? {
        guard let open = text.range(of: "```") else { return nil }
        var body = text[open.upperBound...]
        if let newline = body.firstIndex(of: "\n"),
           body[body.startIndex..<newline].allSatisfy({ $0.isLetter }) {
            body = body[body.index(after: newline)...]
        }
        if let close = body.range(of: "```") {
            body = body[body.startIndex..<close.lowerBound]
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Outermost balanced `{…}`, skipping braces inside string literals.
    /// Rescues responses like `Sure, here's the analysis: {…}` — previously a
    /// total loss even though the object itself was well-formed.
    nonisolated private static func balancedObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if inString && character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - Question Answering

    func askQuestion(
        _ question: String,
        transcript: String,
        episodeTitle: String,
        podcastLanguage: String? = nil,
        progressCallback: (@Sendable (String, Double) -> Void)? = nil
    ) async throws -> CloudQAResult {
        let provider = settings.selectedProvider
        let apiKey = settings.currentAPIKey
        let model = settings.currentModel

        // Format transcript based on user's preference (segment-based vs sentence-based)
        let formattedTranscript = settings.transcriptFormat.formatTranscript(transcript)

        // Handle Apple PCC via Shortcuts
        if provider == .applePCC {
            return try await askQuestionWithShortcuts(
                question: question,
                transcript: formattedTranscript,
                episodeTitle: episodeTitle,
                podcastLanguage: podcastLanguage,
                progressCallback: progressCallback
            )
        }

        if provider.requiresAPIKey {
            guard !apiKey.isEmpty else {
                throw CloudAIError.noAPIKey
            }
        }

        progressCallback?("Processing question...", 0.2)

        // Get language instruction based on user setting
        let languageInstruction = settings.analysisLanguage.getLanguageInstruction(podcastLanguage: podcastLanguage, customLanguageName: settings.customAnalysisLanguageName)
        let languageLine = languageInstruction.isEmpty ? "" : "\n\n\(languageInstruction)"

        // Log the language setting
        logger.info("Q&A Request - Provider: \(provider.displayName), Language setting: \(self.settings.analysisLanguage.rawValue), Instruction: \(languageInstruction.isEmpty ? "None" : languageInstruction)")

        let systemPrompt = """
        You are a helpful assistant that answers questions about podcast episodes.
        Base your answers ONLY on the provided transcript.
        If the answer is not in the transcript, say so clearly.

        IMPORTANT: Return ONLY valid JSON with no additional text, markdown, or code blocks.

        Return JSON in this exact format:
        {
            "answer": "Your detailed answer to the question",
            "confidence": "high/medium/low based on how clearly the transcript addresses this",
            "relatedTopics": ["topic1", "topic2"] or null if none,
            "sources": ["Brief quote or reference from transcript"] or null if none
        }\(languageLine)
        """

        let timestampNote = settings.transcriptFormat == .segmentBased
            ? "\nNote: The transcript includes timestamps in [MM:SS] or [H:MM:SS] format. Include relevant timestamps in your sources."
            : ""

        let userPrompt = """
        Episode: \(episodeTitle)

        Question: \(question)\(timestampNote)

        Transcript:
        \(formattedTranscript)
        """

        progressCallback?("Getting answer from \(provider.displayName)...", 0.5)

        let providerClient = client(for: provider)
        let response = try await providerClient.sendRequest(
            prompt: userPrompt,
            systemPrompt: systemPrompt,
            apiKey: apiKey,
            model: model,
            maxTokens: 8192,
            disableThinking: provider.usesLocalServer && settings.disableThinkingForLocalModels
        )

        progressCallback?("Parsing response...", 0.9)

        // Clean and parse the response
        let cleanedResponse = cleanJSONResponse(response)
        let parsed = parseJSON(cleanedResponse, as: ParsedQAResponse.self)

        // Log the response
        logger.info("Q&A Response received - Parsed successfully: \(parsed != nil)")

        var jsonParseWarning: String?
        if parsed == nil {
            jsonParseWarning = "JSON parsing failed - showing raw response"
            logger.warning("Q&A JSON parsing failed, falling back to raw response")
        }

        progressCallback?("Done", 1.0)

        return CloudQAResult(
            question: question,
            answer: parsed?.answer ?? formatRawResponseForDisplay(response),
            confidence: parsed?.confidence ?? "unknown",
            relatedTopics: parsed?.relatedTopics,
            sources: parsed?.sources,
            provider: provider,
            model: model,
            timestamp: Date(),
            jsonParseWarning: jsonParseWarning
        )
    }

    // MARK: - Public: Prompt Preview

    /// Assembles the same (system, user) prompt pair that would be sent to a cloud
    /// provider for `type`, without actually invoking the model. Used by the
    /// "Copy prompt" affordance so users can paste it into an external tool.
    ///
    /// - Parameter transcriptFormatOverride: When non-nil, formats the transcript and
    ///   tailors timestamp-related instructions to this format instead of the user's
    ///   saved `settings.transcriptFormat`. Used by the prompt preview sheet so users
    ///   can toggle timestamps for export without changing their saved setting.
    func buildPrompt(
        type: CloudAnalysisType,
        transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        podcastLanguage: String? = nil,
        formatHint: String? = nil,
        speakerBlock: String = "",
        transcriptFormatOverride: TranscriptFormatForAI? = nil,
        plainText: Bool = false
    ) -> (system: String, user: String) {
        let effectiveFormat = transcriptFormatOverride ?? settings.transcriptFormat
        // Match the real analyze path: format the raw SRT into the chosen shape
        // before embedding it in the user prompt.
        let formattedTranscript = effectiveFormat.formatTranscript(transcript)
        let system = buildSystemPrompt(
            for: type,
            podcastLanguage: podcastLanguage,
            formatHint: formatHint,
            speakerBlock: speakerBlock,
            transcriptFormatOverride: effectiveFormat,
            plainText: plainText
        )
        let user = buildUserPrompt(
            transcript: formattedTranscript,
            episodeTitle: episodeTitle,
            podcastTitle: podcastTitle,
            analysisType: type,
            formatHint: formatHint,
            speakerBlock: speakerBlock,
            transcriptFormatOverride: effectiveFormat
        )
        return (system, user)
    }

    // MARK: - Private: Build Prompts

    private func buildSystemPrompt(for type: CloudAnalysisType, podcastLanguage: String? = nil, formatHint: String? = nil, speakerBlock: String = "", transcriptFormatOverride: TranscriptFormatForAI? = nil, plainText: Bool = false) -> String {
        // Get language instruction based on user setting
        let languageInstruction = settings.analysisLanguage.getLanguageInstruction(podcastLanguage: podcastLanguage, customLanguageName: settings.customAnalysisLanguageName)
        let languageLine = languageInstruction.isEmpty ? "" : "\n\n\(languageInstruction)"

        let formatHintLine: String
        if let hint = formatHint, !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            formatHintLine = "\n\nPodcast Format Context: \(hint)\nUse this to understand the episode structure and skip any sponsored/advertisement segments in your analysis."
        } else {
            formatHintLine = "\n\nNote: If the transcript contains sponsored or advertisement segments, ignore them — do not include ads in topics, takeaways, highlights, or quotes."
        }

        let effectiveFormat = transcriptFormatOverride ?? settings.transcriptFormat

        switch type {
        case .analysis:
            let useTimestamps = effectiveFormat == .segmentBased

            // Plain-text variant: a readable answer for users chatting with an LLM
            // about the episode, rather than the JSON the app parses.
            if plainText {
                let quoteTimestampNote = useTimestamps
                    ? " (include the [MM:SS] timestamp for each quote)"
                    : ""
                return """
                You are an expert podcast analyst. Answer in clear, readable plain text — use short headings and bullet points where helpful. Do NOT return JSON or code blocks; write it as if explaining the episode to a curious listener.

                Cover: a 2–3 paragraph overview; the main topics with their key points; key takeaways and insights; notable people, organizations, products, and resources mentioned; highlights; memorable quotes\(quoteTimestampNote); any action items; and a short conclusion on who would benefit.\(formatHintLine)\(speakerBlock)\(languageLine)
                """
            }

            let quotesSchema = useTimestamps
                ? #""notableQuotes": [{"text": "quote 1", "timestamp": "MM:SS"}, {"text": "quote 2", "timestamp": "MM:SS"}]"#
                : #""notableQuotes": ["quote 1", "quote 2"]"#
            let quotesNote = useTimestamps
                ? "\nFor each notable quote, include the timestamp where it appears in the transcript. Use MM:SS or H:MM:SS format."
                : ""
            return """
            You are an expert podcast analyst. Create a single comprehensive analysis that combines summary, entities, highlights, and strategic takeaways.

            IMPORTANT: Return ONLY valid JSON with no additional text.

            Return JSON in this exact format:
            {
                "overview": "2-3 paragraph executive summary of the episode",
                "mainTopics": [
                    {
                        "topic": "Topic Name",
                        "summary": "Brief summary of this topic",
                        "keyPoints": ["point 1", "point 2"]
                    }
                ],
                "keyTakeaways": ["takeaway 1", "takeaway 2", "takeaway 3"],
                "keyInsights": ["insight 1", "insight 2", "insight 3"],
                "targetAudience": "Description of who would benefit from this episode",
                "engagementLevel": "high/medium/low",
                "people": ["person1", "person2"],
                "organizations": ["org1", "org2"],
                "products": ["product1", "product2"],
                "locations": ["location1", "location2"],
                "resources": ["book1", "article1"],
                "highlights": ["highlight1", "highlight2", "highlight3"],
                \(quotesSchema),
                "actionItems": ["action1", "action2"],
                "controversialPoints": ["point1"] or null,
                "entertainingMoments": ["moment1"] or null,
                "qaHighlights": [{"question": "question text", "answer": "answer text"}] or null if no Q&A section exists,
                "conclusion": "Overall assessment and who would benefit from this episode"
            }\(quotesNote)\(formatHintLine)\(speakerBlock)\(languageLine)
            """
        }
    }

    private func buildUserPrompt(
        transcript: String,
        episodeTitle: String,
        podcastTitle: String,
        analysisType: CloudAnalysisType,
        formatHint: String? = nil,
        speakerBlock: String = "",
        transcriptFormatOverride: TranscriptFormatForAI? = nil
    ) -> String {
        let instruction: String
        switch analysisType {
        case .analysis:
            instruction = "Please provide one complete analysis of this podcast episode, covering summary, topics, entities, highlights, quotes, action items, and conclusion."
        }

        let effectiveFormat = transcriptFormatOverride ?? settings.transcriptFormat
        // When using segment-based format, tell the AI timestamps are present so it uses them
        let timestampNote = effectiveFormat == .segmentBased
            ? "\nNote: The transcript includes timestamps in [MM:SS] or [H:MM:SS] format. Reference these timestamps when relevant (e.g. for highlights, quotes, and key moments)."
            : ""

        return """
        Podcast: \(podcastTitle)
        Episode: \(episodeTitle)

        \(instruction)\(timestampNote)

        Transcript:
        \(transcript)
        """
    }
}

// MARK: - Supporting Types

enum CloudAnalysisType: String, CaseIterable {
    case analysis = "Analysis"

    var icon: String {
        switch self {
        case .analysis: return "sparkles"
        }
    }
}

struct CloudAnalysisResult {
    let type: CloudAnalysisType
    let content: String
    let parsedAnalysis: ParsedEpisodeAnalysisResponse?
    let provider: CloudAIProvider
    let model: String
    let timestamp: Date
    /// Warning message when JSON parsing fails (e.g., when using Shortcuts)
    let jsonParseWarning: String?

    init(
        type: CloudAnalysisType,
        content: String,
        parsedAnalysis: ParsedEpisodeAnalysisResponse? = nil,
        provider: CloudAIProvider,
        model: String,
        timestamp: Date,
        jsonParseWarning: String? = nil
    ) {
        self.type = type
        self.content = content
        self.parsedAnalysis = parsedAnalysis
        self.provider = provider
        self.model = model
        self.timestamp = timestamp
        self.jsonParseWarning = jsonParseWarning
    }
}

struct CloudQAResult: Sendable {
    let question: String
    let answer: String
    let confidence: String
    let relatedTopics: [String]?
    let sources: [String]?
    let provider: CloudAIProvider
    let model: String
    let timestamp: Date
    /// Warning message when JSON parsing fails
    let jsonParseWarning: String?

    nonisolated init(
        question: String,
        answer: String,
        confidence: String = "unknown",
        relatedTopics: [String]? = nil,
        sources: [String]? = nil,
        provider: CloudAIProvider,
        model: String,
        timestamp: Date,
        jsonParseWarning: String? = nil
    ) {
        self.question = question
        self.answer = answer
        self.confidence = confidence
        self.relatedTopics = relatedTopics
        self.sources = sources
        self.provider = provider
        self.model = model
        self.timestamp = timestamp
        self.jsonParseWarning = jsonParseWarning
    }
}

enum CloudAIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case networkError(Error)
    case quotaExceeded(provider: String)
    case invalidAPIKey(provider: String)
    case modelNotFound(model: String)
    case rateLimited(provider: String)
    case contextTooLong(provider: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your API key in Settings > AI Settings."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .apiError(let statusCode, let message):
            return parseAPIError(statusCode: statusCode, message: message)
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .quotaExceeded(let provider):
            return "API quota exceeded for \(provider). Please check your billing/usage limits or try again later."
        case .invalidAPIKey(let provider):
            return "Invalid API key for \(provider). Please check your API key in Settings > AI Settings."
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Please select a different model in Settings > AI Settings."
        case .rateLimited(let provider):
            return "Too many requests to \(provider). Please wait a moment and try again."
        case .contextTooLong(let provider):
            return "Transcript too long for \(provider). Try a shorter episode or use a model with larger context window."
        }
    }

    private func parseAPIError(statusCode: Int, message: String) -> String {
        let lowercaseMessage = message.lowercased()

        switch statusCode {
        case 401:
            return "Invalid or expired API key. Please check your API key in Settings."
        case 403:
            return "Access denied. Your API key may not have permission for this model."
        case 404:
            if lowercaseMessage.contains("model") {
                return "Model not found. Please select a different model in Settings > AI Settings."
            }
            return "Resource not found. Please try again."
        case 429:
            if lowercaseMessage.contains("quota") || lowercaseMessage.contains("exceeded") {
                return "API quota exceeded. Please check your billing limits or upgrade your plan."
            }
            return "Rate limit exceeded. Please wait a moment and try again."
        case 500, 502, 503:
            return "AI service temporarily unavailable. Please try again later."
        case 400:
            if lowercaseMessage.contains("context") || lowercaseMessage.contains("token") || lowercaseMessage.contains("length") {
                return "Transcript too long. Try a shorter episode or use a model with larger context."
            }
            return "Invalid request: \(message)"
        case 0:
            // statusCode 0 is used for non-HTTP failures (e.g. Shortcuts execution).
            // Show the underlying message directly instead of the misleading "API error (0)" prefix.
            return message
        default:
            return "API error (\(statusCode)): \(message)"
        }
    }
}
