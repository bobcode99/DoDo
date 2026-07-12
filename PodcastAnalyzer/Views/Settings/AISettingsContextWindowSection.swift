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

                HStack {
                    Text(settings.selectedProvider.displayName)
                    Spacer()
                    Text("\(formatNumber(settings.selectedProvider.contextWindowSize)) tokens")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        } header: {
            Text("Context Window Comparison")
        } footer: {
            Text("Larger context windows allow analyzing longer transcripts in a single request, resulting in better quality summaries.")
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}
