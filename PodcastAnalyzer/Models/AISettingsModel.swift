//
//  AISettingsModel.swift
//  PodcastAnalyzer
//
//  Settings for AI providers (Cloud APIs with BYOK)
//

import SwiftUI
import Foundation

// MARK: - Transcript Format for AI Analysis

nonisolated enum TranscriptFormatForAI: String, CaseIterable, Codable {
    case segmentBased = "Segment-Based"
    case sentenceBased = "Sentence-Based"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .segmentBased: return "list.bullet.rectangle"
        case .sentenceBased: return "text.alignleft"
        }
    }

    var description: String {
        switch self {
        case .segmentBased: return "Include timestamps with each segment, e.g. [00:01:23] text (useful for time references)"
        case .sentenceBased: return "Merge segments into natural sentences (better for AI comprehension, lower token cost)"
        }
    }

    /// Format transcript content based on the selected format
    /// - Parameter transcript: Raw SRT transcript content
    /// - Returns: Formatted transcript suitable for AI analysis
    func formatTranscript(_ transcript: String) -> String {
        switch self {
        case .segmentBased:
            // Convert SRT to clean "[HH:MM:SS] text" format for AI
            if transcript.contains("-->") {
                return formatSegmentBased(transcript)
            }
            // Already plain text — return as-is (no timestamps available)
            return transcript
        case .sentenceBased:
            // Check if content looks like SRT/VTT format (has timestamps)
            if transcript.contains("-->") {
                // Use SRTParser to extract plain text, then merge into sentences
                let plainText = SRTParser.extractPlainText(from: transcript)
                return mergeSentences(plainText)
            } else {
                // Already plain text, just merge sentences
                return mergeSentences(transcript)
            }
        }
    }

    /// Convert SRT content to clean "[HH:MM:SS] text" lines for AI
    private func formatSegmentBased(_ srtContent: String) -> String {
        let segments = SRTParser.parseSegments(from: srtContent)
        return segments.map { segment in
            let totalSeconds = Int(segment.startTime)
            let h = totalSeconds / 3600
            let m = (totalSeconds % 3600) / 60
            let s = totalSeconds % 60
            let timestamp = h > 0
                ? String(format: "[%d:%02d:%02d]", h, m, s)
                : String(format: "[%02d:%02d]", m, s)
            return "\(timestamp) \(segment.text)"
        }.joined(separator: "\n")
    }

    /// Merge text segments into proper sentences for better AI comprehension
    /// Handles sentence-ending punctuation for multiple languages
    private func mergeSentences(_ text: String) -> String {
        // Sentence endings for multiple languages
        let sentenceEndings = CharacterSet(charactersIn: ".!?。！？")

        // Split by whitespace and recombine intelligently
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        var sentences: [String] = []
        var currentSentence: [String] = []

        for word in words {
            currentSentence.append(word)

            // Check if this word ends with sentence-ending punctuation
            let trimmedWord = word.trimmingCharacters(in: .whitespaces)
            if let lastChar = trimmedWord.unicodeScalars.last,
               sentenceEndings.contains(lastChar) {
                // End of sentence - join and add to sentences
                sentences.append(currentSentence.joined(separator: " "))
                currentSentence = []
            }
        }

        // Handle remaining words that didn't end with punctuation
        if !currentSentence.isEmpty {
            sentences.append(currentSentence.joined(separator: " "))
        }

        // Join sentences with newlines for better readability
        return sentences.joined(separator: "\n")
    }
}

// MARK: - Analysis Language Setting

nonisolated enum AnalysisLanguage: String, CaseIterable, Codable {
    // Behaviour-based options
    case deviceLanguage = "Device Language"
    case matchPodcast = "Match Podcast"

    // Popular languages (alphabetical within each script family for predictable picker order)
    case english = "English"
    case spanish = "Spanish"
    case french = "French"
    case german = "German"
    case italian = "Italian"
    case portuguese = "Portuguese"
    case dutch = "Dutch"
    case russian = "Russian"
    case arabic = "Arabic"
    case hindi = "Hindi"
    case chineseSimplified = "Chinese (Simplified)"
    case chineseTraditional = "Chinese (Traditional)"
    case japanese = "Japanese"
    case korean = "Korean"

    // Custom override — paired with `customAnalysisLanguageName` in AISettingsManager.
    case custom = "Custom…"

    var displayName: String { rawValue }

    /// Groups picker entries into Behaviour / Popular Languages / Custom.
    static var behaviorCases: [AnalysisLanguage] { [.deviceLanguage, .matchPodcast] }
    static var popularLanguageCases: [AnalysisLanguage] {
        [.english, .spanish, .french, .german, .italian, .portuguese, .dutch,
         .russian, .arabic, .hindi,
         .chineseSimplified, .chineseTraditional, .japanese, .korean]
    }

    var icon: String {
        switch self {
        case .deviceLanguage: return "iphone"
        case .matchPodcast: return "waveform"
        case .english: return "globe.americas"
        case .spanish, .portuguese: return "globe.europe.africa"
        case .french, .german, .italian, .dutch, .russian: return "globe.europe.africa"
        case .arabic, .hindi: return "globe"
        case .chineseSimplified, .chineseTraditional, .japanese, .korean: return "globe.asia.australia"
        case .custom: return "pencil.line"
        }
    }

    /// Emoji equivalent of `icon` — flags for languages, semantic glyphs for
    /// the behavior / custom modes. Used by the Response Language picker.
    var emoji: String {
        switch self {
        case .deviceLanguage: return "📱"
        case .matchPodcast: return "🎙️"
        case .english: return "🇬🇧"
        case .spanish: return "🇪🇸"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .italian: return "🇮🇹"
        case .portuguese: return "🇵🇹"
        case .dutch: return "🇳🇱"
        case .russian: return "🇷🇺"
        case .arabic: return "🇸🇦"
        case .hindi: return "🇮🇳"
        case .chineseSimplified: return "🇨🇳"
        case .chineseTraditional: return "🇹🇼"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        case .custom: return "✏️"
        }
    }

    var description: String {
        switch self {
        case .deviceLanguage: return "Use your device's language settings"
        case .matchPodcast: return "Match the podcast's language"
        case .custom: return "Type any language you want responses in"
        default: return "Always respond in \(rawValue)"
        }
    }

    /// Returns the language instruction to include in AI prompts.
    /// `customLanguageName` is only consulted when `self == .custom`.
    func getLanguageInstruction(
        podcastLanguage: String? = nil,
        customLanguageName: String? = nil
    ) -> String {
        switch self {
        case .deviceLanguage:
            let preferredLanguage = Locale.preferredLanguages.first ?? "en"
            let languageName = Locale.current.localizedString(forLanguageCode: preferredLanguage) ?? "English"
            return "IMPORTANT: Respond in \(languageName)."
        case .matchPodcast:
            if let podcastLang = podcastLanguage, !podcastLang.isEmpty {
                let languageName = Locale.current.localizedString(forLanguageCode: podcastLang) ?? podcastLang
                return "IMPORTANT: Respond in \(languageName) (the podcast's language)."
            }
            return "" // No instruction if podcast language unknown
        case .custom:
            let trimmed = (customLanguageName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            return "IMPORTANT: Respond in \(trimmed)."
        default:
            return "IMPORTANT: Respond in \(rawValue)."
        }
    }
}

// MARK: - Cloud AI Provider

nonisolated enum CloudAIProvider: String, CaseIterable, Codable, Sendable {
    case applePCC = "Apple PCC"  // Apple Private Cloud Compute via Shortcuts
    case openai = "OpenAI"
    case claude = "Claude"
    case gemini = "Gemini"
    case groq = "Groq"
    case grok = "Grok"
    case lmstudio = "LMStudio"
    case ollama = "Ollama"

    var displayName: String {
        switch self {
        case .applePCC: return "Shortcuts"
        case .lmstudio: return "LM Studio"
        case .ollama: return "Ollama"
        default: return rawValue
        }
    }

    var iconName: String {
        switch self {
        case .applePCC: return "arrow.triangle.branch"
        case .openai: return "brain.head.profile"
        case .claude: return "sparkles"
        case .gemini: return "diamond"
        case .groq: return "hare"
        case .grok: return "bolt"
        case .lmstudio: return "desktopcomputer"
        case .ollama: return "server.rack"
        }
    }

    var apiKeyURL: URL? {
        switch self {
        case .applePCC, .lmstudio, .ollama: return nil
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")
        case .groq: return URL(string: "https://console.groq.com/keys")
        case .grok: return URL(string: "https://console.x.ai/")
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .applePCC, .lmstudio, .ollama: return false
        default: return true
        }
    }

    /// Whether this provider runs on a local server with a configurable URL
    var usesLocalServer: Bool {
        self == .lmstudio || self == .ollama
    }

    /// Where the provider publishes its current rates.
    ///
    /// Deliberately a link and not a number. The `pricingNote` this replaced
    /// quoted per-token prices and "free tier available!" from whenever it was
    /// typed; by the time anyone read it in the app the figures were wrong and
    /// the free tiers had changed shape. A URL is the only claim about someone
    /// else's pricing that stays true without maintenance.
    var pricingURL: URL? {
        switch self {
        case .applePCC, .lmstudio, .ollama: return nil
        case .openai: return URL(string: "https://openai.com/api/pricing/")
        case .claude: return URL(string: "https://platform.claude.com/docs/en/about-claude/pricing")
        case .gemini: return URL(string: "https://ai.google.dev/gemini-api/docs/pricing")
        case .groq: return URL(string: "https://groq.com/pricing")
        case .grok: return URL(string: "https://docs.x.ai/docs/models")
        }
    }

    /// One line about what running this provider costs, in kind rather than in
    /// numbers — the part that does not change when a price list does.
    var costSummary: LocalizedStringKey {
        switch self {
        case .applePCC: return "Runs through the Shortcuts app. Cost depends on the shortcut you build."
        case .lmstudio: return "Runs locally in LM Studio. No API cost."
        case .ollama: return "Runs locally in Ollama. No API cost."
        default: return "Billed per token by the provider, against your own API key."
        }
    }

    /// Whether this provider uses Shortcuts for AI processing
    var usesShortcuts: Bool {
        self == .applePCC
    }
}

// MARK: - AI Settings Manager

@Observable
final class AISettingsManager {
    static let shared = AISettingsManager()

    // MARK: - Stored Properties

    var selectedProvider: CloudAIProvider {
        didSet { saveSettings() }
    }

    var openAIKey: String {
        didSet { saveToKeychain(key: openAIKey, for: .openai) }
    }

    var claudeKey: String {
        didSet { saveToKeychain(key: claudeKey, for: .claude) }
    }

    var geminiKey: String {
        didSet { saveToKeychain(key: geminiKey, for: .gemini) }
    }

    var grokKey: String {
        didSet { saveToKeychain(key: grokKey, for: .grok) }
    }

    var groqKey: String {
        didSet { saveToKeychain(key: groqKey, for: .groq) }
    }

    /// Optional Bearer token for LM Studio when its "Manage Tokens" auth is on
    /// (LM Studio 0.4.0+). Empty string disables the Authorization header.
    /// Stored in Keychain like other provider keys.
    var lmstudioKey: String {
        didSet { saveToKeychain(key: lmstudioKey, for: .lmstudio) }
    }

    var selectedOpenAIModel: String {
        didSet { saveSettings() }
    }

    var selectedClaudeModel: String {
        didSet { saveSettings() }
    }

    var selectedGeminiModel: String {
        didSet { saveSettings() }
    }

    var selectedGrokModel: String {
        didSet { saveSettings() }
    }

    var selectedGroqModel: String {
        didSet { saveSettings() }
    }

    var selectedLMStudioModel: String {
        didSet { saveSettings() }
    }

    var selectedOllamaModel: String {
        didSet { saveSettings() }
    }

    var disableThinkingForLocalModels: Bool {
        didSet { saveSettings() }
    }

    var analysisLanguage: AnalysisLanguage {
        didSet { saveSettings() }
    }

    /// Free-form language name used when `analysisLanguage == .custom`.
    /// Persisted separately so users can type any language (e.g. "Swiss German").
    var customAnalysisLanguageName: String {
        didSet { UserDefaults.standard.set(customAnalysisLanguageName, forKey: "ai_custom_analysis_language") }
    }

    var transcriptFormat: TranscriptFormatForAI {
        didSet { saveSettings() }
    }

    var shortcutsTimeout: TimeInterval {
        didSet { UserDefaults.standard.set(shortcutsTimeout, forKey: "ai_shortcuts_timeout") }
    }

    // MARK: - Podcast Format Hints

    /// Returns the saved format hint for a given podcast title, or empty string if none set.
    func formatHint(for podcastTitle: String) -> String {
        let hints = loadFormatHints()
        return hints[podcastTitle] ?? ""
    }

    /// Saves a format hint for a podcast title.
    func saveFormatHint(_ hint: String, for podcastTitle: String) {
        var hints = loadFormatHints()
        if hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hints.removeValue(forKey: podcastTitle)
        } else {
            hints[podcastTitle] = hint
        }
        if let data = try? JSONEncoder().encode(hints) {
            UserDefaults.standard.set(data, forKey: "ai_podcast_format_hints")
        }
    }

    private func loadFormatHints() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: "ai_podcast_format_hints"),
              let hints = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return hints
    }

    /// All saved per-podcast format hints, keyed by podcast title. Used by backup export.
    var allFormatHints: [String: String] {
        loadFormatHints()
    }

    // MARK: - Local Server URLs

    var lmstudioBaseURL: URL {
        get {
            let str = UserDefaults.standard.string(forKey: "ai_lmstudio_base_url")
                ?? "http://localhost:1234"
            return URL(string: str) ?? URL(string: "http://localhost:1234")!
        }
        set {
            UserDefaults.standard.set(newValue.absoluteString, forKey: "ai_lmstudio_base_url")
        }
    }

    var ollamaBaseURL: URL {
        get {
            let str = UserDefaults.standard.string(forKey: "ai_ollama_base_url")
                ?? "http://localhost:11434"
            return URL(string: str) ?? URL(string: "http://localhost:11434")!
        }
        set {
            UserDefaults.standard.set(newValue.absoluteString, forKey: "ai_ollama_base_url")
        }
    }

    // MARK: - Initialization

    private init() {
        // Load provider selection
        if let providerString = UserDefaults.standard.string(forKey: "ai_selected_provider"),
           let provider = CloudAIProvider(rawValue: providerString) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .gemini
        }

        // Load model selections. No seeded defaults: a hardcoded starter id
        // rots into a 404, so an unconfigured provider starts with no model and
        // the first successful model fetch picks one from the live catalogue.
        self.selectedOpenAIModel = UserDefaults.standard.string(forKey: "ai_openai_model") ?? ""
        self.selectedClaudeModel = UserDefaults.standard.string(forKey: "ai_claude_model") ?? ""
        self.selectedGeminiModel = UserDefaults.standard.string(forKey: "ai_gemini_model") ?? ""
        self.selectedGrokModel = UserDefaults.standard.string(forKey: "ai_grok_model") ?? ""
        self.selectedGroqModel = UserDefaults.standard.string(forKey: "ai_groq_model") ?? ""
        self.selectedLMStudioModel = UserDefaults.standard.string(forKey: "ai_lmstudio_model") ?? ""
        self.selectedOllamaModel = UserDefaults.standard.string(forKey: "ai_ollama_model") ?? ""
        self.disableThinkingForLocalModels = UserDefaults.standard.bool(forKey: "ai_disable_thinking")

        // Load analysis language setting
        if let languageString = UserDefaults.standard.string(forKey: "ai_analysis_language"),
           let language = AnalysisLanguage(rawValue: languageString) {
            self.analysisLanguage = language
        } else {
            self.analysisLanguage = .deviceLanguage // Default
        }

        // Load custom analysis language name (only meaningful when analysisLanguage == .custom)
        self.customAnalysisLanguageName = UserDefaults.standard.string(forKey: "ai_custom_analysis_language") ?? ""

        // Load transcript format setting
        if let formatString = UserDefaults.standard.string(forKey: "ai_transcript_format"),
           let format = TranscriptFormatForAI(rawValue: formatString) {
            self.transcriptFormat = format
        } else {
            self.transcriptFormat = .sentenceBased // Default to sentence-based for better AI comprehension
        }

        // Load shortcuts timeout setting
        self.shortcutsTimeout = UserDefaults.standard.object(forKey: "ai_shortcuts_timeout") as? TimeInterval ?? 120

        // Load API keys from Keychain (use static method to avoid 'self' issue)
        self.openAIKey = Self.loadKeyFromKeychain(for: .openai)
        self.claudeKey = Self.loadKeyFromKeychain(for: .claude)
        self.geminiKey = Self.loadKeyFromKeychain(for: .gemini)
        self.grokKey = Self.loadKeyFromKeychain(for: .grok)
        self.groqKey = Self.loadKeyFromKeychain(for: .groq)
        self.lmstudioKey = Self.loadKeyFromKeychain(for: .lmstudio)
    }

    // MARK: - Computed Properties

    var hasConfiguredProvider: Bool {
        if !selectedProvider.requiresAPIKey {
            return true
        }
        return !currentAPIKey.isEmpty
    }

    var currentAPIKey: String {
        switch selectedProvider {
        case .applePCC, .ollama: return ""
        case .lmstudio: return lmstudioKey  // optional Bearer token
        case .openai: return openAIKey
        case .claude: return claudeKey
        case .gemini: return geminiKey
        case .groq: return groqKey
        case .grok: return grokKey
        }
    }

    var currentModel: String {
        switch selectedProvider {
        case .applePCC: return "Shortcuts"
        case .openai: return selectedOpenAIModel
        case .claude: return selectedClaudeModel
        case .gemini: return selectedGeminiModel
        case .groq: return selectedGroqModel
        case .grok: return selectedGrokModel
        case .lmstudio: return selectedLMStudioModel
        case .ollama: return selectedOllamaModel
        }
    }

    func apiKey(for provider: CloudAIProvider) -> String {
        switch provider {
        case .applePCC, .ollama: return ""
        case .lmstudio: return lmstudioKey
        case .openai: return openAIKey
        case .claude: return claudeKey
        case .gemini: return geminiKey
        case .groq: return groqKey
        case .grok: return grokKey
        }
    }

    func setAPIKey(_ key: String, for provider: CloudAIProvider) {
        switch provider {
        case .applePCC, .ollama: break
        case .lmstudio: lmstudioKey = key
        case .openai: openAIKey = key
        case .claude: claudeKey = key
        case .gemini: geminiKey = key
        case .groq: groqKey = key
        case .grok: grokKey = key
        }
    }

    // MARK: - Persistence

    private func saveSettings() {
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: "ai_selected_provider")
        UserDefaults.standard.set(selectedOpenAIModel, forKey: "ai_openai_model")
        UserDefaults.standard.set(selectedClaudeModel, forKey: "ai_claude_model")
        UserDefaults.standard.set(selectedGeminiModel, forKey: "ai_gemini_model")
        UserDefaults.standard.set(selectedGrokModel, forKey: "ai_grok_model")
        UserDefaults.standard.set(selectedGroqModel, forKey: "ai_groq_model")
        UserDefaults.standard.set(selectedLMStudioModel, forKey: "ai_lmstudio_model")
        UserDefaults.standard.set(selectedOllamaModel, forKey: "ai_ollama_model")
        UserDefaults.standard.set(disableThinkingForLocalModels, forKey: "ai_disable_thinking")
        UserDefaults.standard.set(analysisLanguage.rawValue, forKey: "ai_analysis_language")
        UserDefaults.standard.set(transcriptFormat.rawValue, forKey: "ai_transcript_format")
    }

    // MARK: - Keychain Helpers

    private static func keychainKeyName(for provider: CloudAIProvider) -> String {
        "com.podcastanalyzer.apikey.\(provider.rawValue.lowercased())"
    }

    private func saveToKeychain(key: String, for provider: CloudAIProvider) {
        let keychainKey = Self.keychainKeyName(for: provider)
        let data = key.data(using: .utf8)!

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new if not empty
        if !key.isEmpty {
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: keychainKey,
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private static func loadKeyFromKeychain(for provider: CloudAIProvider) -> String {
        let keychainKey = keychainKeyName(for: provider)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }
}
