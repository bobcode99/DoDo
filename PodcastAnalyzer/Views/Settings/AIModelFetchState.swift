//
//  AIModelFetchState.swift
//  PodcastAnalyzer
//
//  Shared model-fetch / test-connection state for AISettingsView's sections.
//

import Foundation

@Observable
final class AIModelFetchState {
    var fetchedModels: [CloudAIProvider: [String]] = [:]
    var isFetchingModels = false
    var modelFetchError: String?

    var isTesting = false
    var showingTestResult = false
    var testResultMessage = ""
    var testResultSuccess = false

    private let settings = AISettingsManager.shared

    /// Fetches models for `provider` only if not already fetched, mirroring
    /// the "auto-fetch when it makes sense" behavior on appear and on
    /// provider change.
    func autoFetchIfNeeded(for provider: CloudAIProvider) {
        if provider.usesLocalServer {
            if fetchedModels[provider] == nil {
                fetchModels(for: provider)
            }
        } else {
            let apiKey = settings.apiKey(for: provider)
            if !apiKey.isEmpty && fetchedModels[provider] == nil {
                fetchModels(for: provider)
            }
        }
    }

    func fetchModels(for provider: CloudAIProvider) {
        let apiKey = settings.apiKey(for: provider)

        // For local providers, don't require API key
        if provider.requiresAPIKey && apiKey.isEmpty {
            return
        }

        isFetchingModels = true
        modelFetchError = nil

        Task {
            do {
                let service = CloudAIService.shared
                let models = try await service.fetchAvailableModels(for: provider, apiKey: apiKey)

                fetchedModels[provider] = models
                isFetchingModels = false

                // If current model is not in the list, select the first available
                let currentModel: String
                switch provider {
                case .applePCC: currentModel = "Shortcuts"
                case .openai: currentModel = settings.selectedOpenAIModel
                case .claude: currentModel = settings.selectedClaudeModel
                case .gemini: currentModel = settings.selectedGeminiModel
                case .groq: currentModel = settings.selectedGroqModel
                case .grok: currentModel = settings.selectedGrokModel
                case .lmstudio: currentModel = settings.selectedLMStudioModel
                case .ollama: currentModel = settings.selectedOllamaModel
                }

                // Only auto-pick a model when none was saved yet. For local
                // servers we deliberately preserve the saved selection even if
                // the model isn't in the current /v1/models list — JIT loaders
                // can still resolve it, and clobbering it surprises the user.
                let shouldAutoSelect: Bool = {
                    if currentModel.isEmpty { return true }
                    if provider.usesLocalServer { return false }
                    return !models.contains(currentModel)
                }()
                if shouldAutoSelect, let firstModel = models.first {
                    switch provider {
                    case .applePCC: break
                    case .openai: settings.selectedOpenAIModel = firstModel
                    case .claude: settings.selectedClaudeModel = firstModel
                    case .gemini: settings.selectedGeminiModel = firstModel
                    case .groq: settings.selectedGroqModel = firstModel
                    case .grok: settings.selectedGrokModel = firstModel
                    case .lmstudio: settings.selectedLMStudioModel = firstModel
                    case .ollama: settings.selectedOllamaModel = firstModel
                    }
                }
            } catch {
                let fallback = provider.availableModels
                if provider.usesLocalServer {
                    modelFetchError = "Cannot connect to \(provider.displayName). Is it running?"
                    fetchedModels[provider] = nil
                } else {
                    modelFetchError = "Could not fetch models. Using defaults."
                    fetchedModels[provider] = fallback
                }
                isFetchingModels = false
            }
        }
    }

    func testConnection() {
        isTesting = true

        Task {
            do {
                let service = CloudAIService.shared
                _ = try await service.testConnection()

                testResultSuccess = true
                testResultMessage = "Connection successful!\n\nProvider: \(settings.selectedProvider.displayName)\nModel: \(settings.currentModel)"
                showingTestResult = true
                isTesting = false
            } catch {
                testResultSuccess = false
                testResultMessage = "Connection failed: \(error.localizedDescription)"
                showingTestResult = true
                isTesting = false
            }
        }
    }
}
