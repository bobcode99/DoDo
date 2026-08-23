//
//  NavRowLabel.swift
//  PodcastAnalyzer
//
//  Tinted-icon row used as the label of the episode detail navigation links
//  (Transcript / AI Insights).
//

#if os(iOS)
import SwiftUI

struct NavRowLabel: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    /// The icon tile tracks Dynamic Type — a fixed frame left it stranded at a
    /// fraction of the label's height at accessibility text sizes.
    @ScaledMetric private var tileSize: Double = 34

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: tileSize, height: tileSize)
                .background(tint.opacity(0.15), in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .bold()
                .foregroundStyle(.tertiary)
                // Decorative: the row is already a link, and VoiceOver was
                // reading "…, chevron right" after every title.
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

#Preview {
    VStack(spacing: 0) {
        NavRowLabel(
            icon: "captions.bubble",
            tint: .purple,
            title: "Transcript",
            subtitle: "Synced · tap a line to seek"
        )
        Divider().padding(.leading, 52)
        NavRowLabel(
            icon: "sparkles",
            tint: .orange,
            title: "AI Insights",
            subtitle: "Summary, takeaways & quotes"
        )
    }
    .background(.regularMaterial, in: .rect(cornerRadius: 16))
    .padding()
}

#endif
