//
//  AISettingsSharedFields.swift
//  PodcastAnalyzer
//
//  Small reusable form fields shared across the AI Settings sections.
//

import SwiftUI

/// Secure field for entering a provider's API key.
struct AIAPIKeyField: View {
    let provider: CloudAIProvider
    let modelState: AIModelFetchState

    @Bindable private var settings = AISettingsManager.shared

    var body: some View {
        let binding = Binding<String>(
            get: { settings.apiKey(for: provider) },
            set: { newValue in
                settings.setAPIKey(newValue, for: provider)
                // Auto-fetch models when API key is entered (or cleared) — the
                // models endpoint may itself require the new token on LM Studio.
                if provider == settings.selectedProvider {
                    modelState.fetchModels(for: provider)
                }
            }
        )

        // LM Studio's token is optional, so flag it as such in the placeholder.
        let placeholder = provider == .lmstudio
            ? "LM Studio API Token (Optional)"
            : "\(provider.displayName) API Key"

        SecureField(placeholder, text: binding)
            .textContentType(.password)
            .autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
    }
}

/// Model picker (or free-text field for local servers with no fetched models).
struct AIModelPicker: View {
    let provider: CloudAIProvider
    let modelState: AIModelFetchState

    @Bindable private var settings = AISettingsManager.shared

    var body: some View {
        let binding: Binding<String> = {
            switch provider {
            case .applePCC:
                return .constant("Shortcuts")
            case .openai:
                return $settings.selectedOpenAIModel
            case .claude:
                return $settings.selectedClaudeModel
            case .gemini:
                return $settings.selectedGeminiModel
            case .groq:
                return $settings.selectedGroqModel
            case .grok:
                return $settings.selectedGrokModel
            case .lmstudio:
                return $settings.selectedLMStudioModel
            case .ollama:
                return $settings.selectedOllamaModel
            }
        }()

        // Use fetched models if available, otherwise use hardcoded defaults.
        // For local servers, surface the saved model in the picker even when
        // it didn't come back from /v1/models — LM Studio's JIT loader can
        // still bring it up on demand, and the user shouldn't lose their
        // selection just because the model isn't currently loaded.
        let fetched = modelState.fetchedModels[provider] ?? provider.availableModels
        let savedSelection = binding.wrappedValue
        let models: [String] = {
            if provider.usesLocalServer
                && !savedSelection.isEmpty
                && !fetched.contains(savedSelection) {
                return [savedSelection] + fetched
            }
            return fetched
        }()

        if models.isEmpty && provider.usesLocalServer {
            HStack {
                Text("Model")
                Spacer()
                TextField("e.g. llama3.2", text: binding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
        } else if models.isEmpty {
            HStack {
                Text("Model")
                Spacer()
                Text("No models loaded")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } else {
            Picker("Model", selection: binding) {
                ForEach(models, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
        }
    }
}

/// Status row shown under the model picker (fetching / error / count).
struct AIModelFetchStatusView: View {
    let provider: CloudAIProvider
    let modelState: AIModelFetchState

    var body: some View {
        if modelState.isFetchingModels {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Fetching available models...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let error = modelState.modelFetchError {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else if let models = modelState.fetchedModels[provider], !models.isEmpty {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("\(models.count) models available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// "Test Connection" button shared by the API key and local server sections.
struct AITestConnectionButton: View {
    let modelState: AIModelFetchState

    @Bindable private var settings = AISettingsManager.shared

    var body: some View {
        Button(action: modelState.testConnection) {
            HStack {
                if modelState.isTesting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "checkmark.circle")
                }
                Text("Test Connection")
            }
        }
        .disabled(
            (settings.selectedProvider.requiresAPIKey && settings.currentAPIKey.isEmpty)
            || modelState.isTesting
        )
    }
}
