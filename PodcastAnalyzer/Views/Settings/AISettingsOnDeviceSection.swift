//
//  AISettingsOnDeviceSection.swift
//  PodcastAnalyzer
//
//  "On-Device AI" info section of AISettingsView.
//
//  This section previously advertised three features. Two of them could not run:
//  Quick Tags lost its UI in a January 2026 refactor and Listening History
//  Summary never had a caller. Both have since been deleted, so the list now
//  names only what actually exists.
//

import SwiftUI

struct AISettingsOnDeviceSection: View {
    private var availability: FoundationModelsAvailability { .current }

    // A section describing a feature this device can never run is noise. It is
    // hidden outright rather than shown with a permanent warning — unlike the
    // fixable states below, which stay visible because they tell the user what
    // to change.
    @ViewBuilder
    var body: some View {
        if FoundationModelsAvailability.isSupported {
            section
        }
    }

    private var section: some View {
        Section {
            HStack {
                Image(systemName: "apple.intelligence")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Apple Foundation Models")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Suggests episodes on Home. No API key needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            statusRow

            featureRow(
                icon: "star.leadinghalf.filled",
                title: "Episode Recommendations",
                description: "Suggests episodes on Home based on what you've played"
            )
        } header: {
            Text("On-Device AI")
        } footer: {
            // Not "no internet required": the model itself has to be downloaded
            // before any of this runs, which is one of the unavailable reasons.
            Text("Runs on your device — your listening history is never uploaded. The model is downloaded once by the system.")
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusRow: some View {
        switch availability {
        case .available:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Available and ready")
                    .font(.caption)
            }
        case .unavailable(let reason):
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(Self.message(for: reason))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Localized copy for each reason.
    ///
    /// These used to be English `String`s built inside the service and rendered
    /// verbatim, which put them out of reach of the string catalog entirely.
    private static func message(for reason: FoundationModelsUnavailableReason) -> LocalizedStringKey {
        switch reason {
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence is off. Turn it on in Settings → Apple Intelligence & Siri."
        case .deviceNotEligible:
            "This device doesn't support Apple Intelligence."
        case .modelNotReady:
            "The system is still downloading the model. This can take a few minutes."
        case .other:
            "Apple Intelligence is unavailable right now."
        }
    }

    // MARK: - Feature row

    /// `LocalizedStringKey`, not `String` — `Text(someString)` silently binds the
    /// non-localizing overload, which is why these strings never reached the
    /// catalog despite being literals at the call site.
    private func featureRow(
        icon: String,
        title: LocalizedStringKey,
        description: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.tint)
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
}
