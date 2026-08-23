//
//  AISettingsContextWindowSection.swift
//  PodcastAnalyzer
//
//  "Context Window Comparison" section of AISettingsView.
//

import SwiftUI

struct AISettingsContextWindowSection: View {
    @Bindable private var settings = AISettingsManager.shared

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("On-Device")
                    Spacer()
                    Text("~4,096 tokens")
                        .foregroundStyle(.secondary)
                }

                // No number for the cloud provider on purpose. This used to
                // print one hardcoded size per provider, but the context window
                // is a property of the model, not the vendor — the same OpenAI
                // key reaches models an order of magnitude apart — so whatever
                // was printed here was wrong for most selections.
                HStack(alignment: .firstTextBaseline) {
                    Text(settings.selectedProvider.displayName)
                    Spacer()
                    Text(settings.currentModel.isEmpty
                         ? "No model selected"
                         : "Set by \(settings.currentModel)")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .font(.subheadline)
        } header: {
            Text("Context Window Comparison")
        } footer: {
            Text("Larger context windows allow analyzing longer transcripts in a single request, resulting in better quality summaries. Cloud limits depend on the model you picked — check your provider's model documentation.")
        }
    }

}
