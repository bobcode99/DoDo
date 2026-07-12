//
//  AISettingsLocalServerSection.swift
//  PodcastAnalyzer
//
//  Local server (LM Studio / Ollama) configuration section of AISettingsView.
//

import SwiftUI

struct AISettingsLocalServerSection: View {
    let modelState: AIModelFetchState

    @Bindable private var settings = AISettingsManager.shared

    @State private var lmstudioURLText: String = ""
    @State private var ollamaURLText: String = ""

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("No API key needed!")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Text("Runs locally on your machine. Make sure \(settings.selectedProvider.displayName) is running before connecting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Base URL configuration
            HStack {
                Text("Server URL")
                Spacer()
                TextField("http://localhost:1234", text: localURLBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            }

            // Optional Bearer token — LM Studio 0.4.0+ supports an
            // optional auth toggle under Server Settings > Manage Tokens.
            // Leave blank if the server doesn't require it.
            if settings.selectedProvider == .lmstudio {
                AIAPIKeyField(provider: .lmstudio, modelState: modelState)
                    .help("Optional. Create one in LM Studio › Developer › Server Settings › Manage Tokens.")
            }

            // Model selection with refresh button
            HStack {
                AIModelPicker(provider: settings.selectedProvider, modelState: modelState)

                Button(action: { modelState.fetchModels(for: settings.selectedProvider) }) {
                    if modelState.isFetchingModels {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(modelState.isFetchingModels)
                .buttonStyle(.borderless)
            }

            AIModelFetchStatusView(provider: settings.selectedProvider, modelState: modelState)

            Toggle(isOn: $settings.disableThinkingForLocalModels) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disable Thinking")
                    Text("Skips chain-of-thought reasoning for faster responses. Best for DeepSeek-R1 and other reasoning models.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            AITestConnectionButton(modelState: modelState)
        } header: {
            Text("\(settings.selectedProvider.displayName) Configuration")
        } footer: {
            if settings.selectedProvider == .lmstudio {
                Text("Default: http://localhost:1234 — Load a model in LM Studio first, then tap refresh.")
            } else {
                Text("Default: http://localhost:11434 — Run 'ollama serve' and pull a model first.")
            }
        }
        .onAppear {
            lmstudioURLText = settings.lmstudioBaseURL.absoluteString
            ollamaURLText = settings.ollamaBaseURL.absoluteString
        }
    }

    /// Binding for the local server URL text field (LMStudio or Ollama)
    private var localURLBinding: Binding<String> {
        switch settings.selectedProvider {
        case .lmstudio:
            return Binding(
                get: { lmstudioURLText },
                set: { newValue in
                    lmstudioURLText = newValue
                    if let url = URL(string: newValue), !newValue.isEmpty {
                        settings.lmstudioBaseURL = url
                    }
                }
            )
        case .ollama:
            return Binding(
                get: { ollamaURLText },
                set: { newValue in
                    ollamaURLText = newValue
                    if let url = URL(string: newValue), !newValue.isEmpty {
                        settings.ollamaBaseURL = url
                    }
                }
            )
        default:
            return .constant("")
        }
    }
}
