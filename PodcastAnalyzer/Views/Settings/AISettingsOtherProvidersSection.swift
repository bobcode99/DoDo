//
//  AISettingsOtherProvidersSection.swift
//  PodcastAnalyzer
//
//  Collapsed "Additional Providers" section for configuring API keys of
//  providers other than the currently selected one.
//

import SwiftUI

struct AISettingsOtherProvidersSection: View {
    let modelState: AIModelFetchState

    @Bindable private var settings = AISettingsManager.shared

    var body: some View {
        Section {
            DisclosureGroup("Configure Other Providers") {
                ForEach(CloudAIProvider.allCases.filter { $0 != settings.selectedProvider && $0.requiresAPIKey }, id: \.self) { provider in
                    VStack(alignment: .leading, spacing: 8) {
                        ProviderIconLabel(provider: provider)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        AIAPIKeyField(provider: provider, modelState: modelState)

                        if !settings.apiKey(for: provider).isEmpty {
                            Label {
                                Text("Key configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }

                        Divider()
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Additional Providers")
        }
    }
}
