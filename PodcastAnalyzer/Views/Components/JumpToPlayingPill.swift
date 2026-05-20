//
//  JumpToPlayingPill.swift
//  PodcastAnalyzer
//
//  Floating glass pill that re-aligns the transcript with audio playback.
//  Shown when the user has paused auto-scroll while the episode is the
//  currently-loaded one, and dismissed during search to avoid clutter.
//

import SwiftUI

struct JumpToPlayingPill: View {
    var isVisible: Bool
    var action: () -> Void

    var body: some View {
        Group {
            if isVisible {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "text.line.first.and.arrowtriangle.forward")
                            .font(.subheadline.weight(.semibold))
                        Text("Jump to playing")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .foregroundStyle(.white)
                    .background(.tint, in: .capsule)
                    .glassEffect(.regular, in: .capsule)
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel("Jump to currently playing sentence")
            }
        }
        .animation(.snappy(duration: 0.25), value: isVisible)
    }
}
