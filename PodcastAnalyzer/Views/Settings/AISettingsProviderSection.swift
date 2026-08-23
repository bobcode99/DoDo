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
                    ProviderIconLabel(provider: provider)
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

            Text(settings.selectedProvider.costSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            // Rates live at the provider, not in this binary. The note that
            // used to sit here quoted per-token prices and free-tier promises
            // that were already out of date when the build shipped.
            if let pricing = settings.selectedProvider.pricingURL {
                Link(destination: pricing) {
                    HStack {
                        Text("View \(settings.selectedProvider.displayName) Pricing")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
            }
        } header: {
            Text("Cloud AI Provider")
        } footer: {
            Text("Cloud AI is used for full transcript analysis. You provide your own API key (BYOK).")
        }
    }
}
