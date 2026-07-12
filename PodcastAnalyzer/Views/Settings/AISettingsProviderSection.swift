//
//  AISettingsProviderSection.swift
//  PodcastAnalyzer
//
//  "Cloud AI Provider" picker section of AISettingsView.
//

import SwiftUI

struct AISettingsProviderSection: View {
    let modelState: AIModelFetchState

    @Bindable private var settings = AISettingsManager.shared

    var body: some View {
        Section {
            Picker("AI Provider", selection: $settings.selectedProvider) {
                ForEach(CloudAIProvider.allCases, id: \.self) { provider in
                    Label(provider.displayName, systemImage: provider.iconName)
                        .tag(provider)
                }
            }
            .onChange(of: settings.selectedProvider) { _, newProvider in
                modelState.autoFetchIfNeeded(for: newProvider)
            }

            if let url = settings.selectedProvider.apiKeyURL {
                Link(destination: url) {
                    HStack {
                        Text("Get \(settings.selectedProvider.displayName) API Key")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }

            Text(settings.selectedProvider.pricingNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Cloud AI Provider")
        } footer: {
            Text("Cloud AI is used for full transcript analysis. You provide your own API key (BYOK).")
        }
    }
}
