//
//  AISettingsOnDeviceSection.swift
//  PodcastAnalyzer
//
//  "On-Device AI" info section of AISettingsView.
//

import SwiftUI

struct AISettingsOnDeviceSection: View {
    @State private var onDeviceAvailability: FoundationModelsAvailability = .unavailable(reason: "Checking...")

    var body: some View {
        Section {
            HStack {
                Image(systemName: "apple.intelligence")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Apple Foundation Models")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Used for quick tags, listening history summary & episode recommendations (no API key needed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Show actual availability status
            HStack {
                if onDeviceAvailability.isAvailable {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Available and ready")
                        .font(.caption)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(onDeviceAvailability.message ?? "Not available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // On-device feature list
            VStack(alignment: .leading, spacing: 6) {
                onDeviceFeatureRow(icon: "tag", title: "Quick Tags", description: "Auto-generate tags from episode metadata")
                onDeviceFeatureRow(icon: "clock.arrow.circlepath", title: "Listening History Summary", description: "Summarize your listening habits and patterns")
                onDeviceFeatureRow(icon: "star.leadinghalf.filled", title: "Episode Recommendations", description: "Get personalized episode suggestions")
            }
        } header: {
            Text("On-Device AI")
        } footer: {
            Text("On-device AI runs completely on your device. No internet required, completely private.")
        }
        .onAppear(perform: checkOnDeviceAvailability)
    }

    private func onDeviceFeatureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func checkOnDeviceAvailability() {
        if #available(iOS 26.0, macOS 26.0, *) {
            Task {
                let service = AppleFoundationModelsService()
                let availability = await service.checkAvailability()

                onDeviceAvailability = availability
            }
        } else {
            onDeviceAvailability = .unavailable(reason: "Requires iOS 26+ / macOS 26+")
        }
    }
}
