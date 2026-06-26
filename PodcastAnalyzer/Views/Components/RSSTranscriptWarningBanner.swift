//
//  RSSTranscriptWarningBanner.swift
//  PodcastAnalyzer
//
//  Slim notice for RSS-sourced transcripts where Dynamic Ad Insertion may
//  cause timestamps to drift from playback. Inline Regenerate link when
//  local audio is available.
//

import SwiftUI

struct RSSTranscriptWarningBanner: View {
    @Binding var showRegenerateConfirmation: Bool
    var hasLocalAudio: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text("Timestamps may drift if the episode includes ads")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            if hasLocalAudio {
                Button {
                    showRegenerateConfirmation = true
                } label: {
                    Text("Regenerate")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                .accessibilityLabel("Regenerate transcript from local audio")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.1))
    }
}
