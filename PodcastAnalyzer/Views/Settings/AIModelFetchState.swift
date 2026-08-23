//
//  AIModelFetchState.swift
//  PodcastAnalyzer
//
//  Shared model-fetch / test-connection state for AISettingsView's sections.
//

import Foundation

@Observable
@MainActor
final class AIModelFetchState {
    var fetchedModels: [CloudAIProvider: [String]] = [:]
    var isFetchingModels = false
    var modelFetchError: String?

    var isTesting = false
    var showingTestResult = false
    var testResultMessage = ""
    var testResultSuccess = false

    private let settings = AISettingsManager.shared

    /// Both probes are held so a new one replaces the one in flight.
    ///
    /// They used to be bare `Task {}` with no handle. Switching provider or
    /// tapping twice left the earlier request running against the old endpoint,
    /// and whichever finished last wrote the result — so a stale failure could
    /// land on top of a fresh success, or clear `isFetchingModels` while the
    /// current fetch was still going.
    private var fetchTask: Task<Void, Never>?
    private var testTask: Task<Void, Never>?

    /// The provider whose fetch is in flight, so a late reply can be discarded
    /// if the user has moved on.
    private var fetchingProvider: CloudAIProvider?

    /// Fetches models for `provider` only if not already fetched, mirroring
    /// the "auto-fetch when it makes sense" behavior on appear and on
    /// provider change.
    func autoFetchIfNeeded(for provider: CloudAIProvider) {
        guard fetchedModels[provider] == nil else { return }
        if provider.usesLocalServer || !settings.apiKey(for: provider).isEmpty {
            fetchModels(for: provider)
        }
    }

    func fetchModels(for provider: CloudAIProvider) {
        let apiKey = settings.apiKey(for: provider)

        // For local providers, don't require API key
        if provider.requiresAPIKey && apiKey.isEmpty {
            return
        }

        fetchTask?.cancel()
        isFetchingModels = true
        modelFetchError = nil
        fetchingProvider = provider

        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let models = try await CloudAIService.shared.fetchAvailableModels(
                    for: provider, apiKey: apiKey
                )
                guard !Task.isCancelled, self.fetchingProvider == provider else { return }
                self.applyFetched(models, for: provider)
            } catch {
                guard !Task.isCancelled, self.fetchingProvider == provider else { return }
                self.applyFetchFailure(error, for: provider)
            }
        }
    }

    private func applyFetched(_ models: [String], for provider: CloudAIProvider) {
        fetchedModels[provider] = models
        isFetchingModels = false
        modelFetchError = models.isEmpty
            ? "\(provider.displayName) returned no usable chat models."
            : nil

        // Only auto-pick a model when none was saved yet. For local servers we
        // deliberately preserve the saved selection even if the model isn't in
        // the current list — JIT loaders can still resolve it, and clobbering it
        // surprises the user.
        let shouldAutoSelect: Bool = {
            if selectedModel(for: provider).isEmpty { return true }
            if provider.usesLocalServer { return false }
            return !models.contains(selectedModel(for: provider))
        }()
        if shouldAutoSelect, let first = models.first {
            select(first, for: provider)
        }
    }

    /// There is no hardcoded list to fall back to any more, and that is the
    /// point: showing a stale catalogue when the live one is unreachable is how
    /// retired model ids stayed selectable long after they stopped working. An
    /// unreachable provider now says so instead of offering fiction.
    private func applyFetchFailure(_ error: Error, for provider: CloudAIProvider) {
        isFetchingModels = false
        fetchedModels[provider] = nil
        if provider.usesLocalServer {
            modelFetchError = "Cannot connect to \(provider.displayName). Is it running at the address above?"
        } else {
            modelFetchError = "Couldn't load \(provider.displayName) models: \(error.localizedDescription)"
        }
    }

    private func selectedModel(for provider: CloudAIProvider) -> String {
        switch provider {
        case .applePCC: "Shortcuts"
        case .openai: settings.selectedOpenAIModel
        case .claude: settings.selectedClaudeModel
        case .gemini: settings.selectedGeminiModel
        case .groq: settings.selectedGroqModel
        case .grok: settings.selectedGrokModel
        case .lmstudio: settings.selectedLMStudioModel
        case .ollama: settings.selectedOllamaModel
        }
    }

    private func select(_ model: String, for provider: CloudAIProvider) {
        switch provider {
        case .applePCC: break
        case .openai: settings.selectedOpenAIModel = model
        case .claude: settings.selectedClaudeModel = model
        case .gemini: settings.selectedGeminiModel = model
        case .groq: settings.selectedGroqModel = model
        case .grok: settings.selectedGrokModel = model
        case .lmstudio: settings.selectedLMStudioModel = model
        case .ollama: settings.selectedOllamaModel = model
        }
    }

    // MARK: - Test Connection

    func testConnection() {
        testTask?.cancel()
        isTesting = true

        testTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await CloudAIService.shared.testConnection()
                guard !Task.isCancelled else { return }
                self.isTesting = false
                self.testResultSuccess = true
                let model = self.settings.currentModel
                self.testResultMessage = """
                    Connection successful!

                    Provider: \(self.settings.selectedProvider.displayName)
                    Model: \(model.isEmpty ? "none selected yet" : model)
                    """
                self.showingTestResult = true
            } catch {
                guard !Task.isCancelled else { return }
                self.isTesting = false
                self.testResultSuccess = false
                self.testResultMessage = "Connection failed: \(error.localizedDescription)"
                self.showingTestResult = true
            }
        }
    }

    /// Drops any probe still in flight — called when the settings screen goes
    /// away so a slow request can't resolve into a view that is gone.
    func cancelProbes() {
        fetchTask?.cancel()
        testTask?.cancel()
        isFetchingModels = false
        isTesting = false
    }
}
