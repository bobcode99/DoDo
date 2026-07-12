//
//  AISettingsAPIKeySection.swift
//  PodcastAnalyzer
//
//  API key + model selection section for cloud providers that require a key.
//

import SwiftUI

struct AISettingsAPIKeySection: View {
    let modelState: AIModelFetchState

    @Bindable private var settings = AISettingsManager.shared

    var body: some View {
        Section {
            AIAPIKeyField(provider: settings.selectedProvider, modelState: modelState)

            // Model selection with refresh button
            HStack {
                AIModelPicker(provider: settings.selectedProvider, modelState: modelState)

                // Refresh models button
                Button(action: { modelState.fetchModels(for: settings.selectedProvider) }) {
                    if modelState.isFetchingModels {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(settings.currentAPIKey.isEmpty || modelState.isFetchingModels)
                .buttonStyle(.borderless)
            }

            AIModelFetchStatusView(provider: settings.selectedProvider, modelState: modelState)

            AITestConnectionButton(modelState: modelState)
        } header: {
            Text("\(settings.selectedProvider.displayName) Configuration")
        } footer: {
            Text("Tap the refresh button to fetch the latest available models from the API.")
        }
    }
}
