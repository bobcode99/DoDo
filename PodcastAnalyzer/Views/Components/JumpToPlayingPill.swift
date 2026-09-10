//
//  JumpToPlayingPill.swift
//  PodcastAnalyzer
//
//  Floating glass pill that re-aligns the transcript with audio playback.
//  Shown when the user has paused auto-scroll while the episode is the
//  currently-loaded one, and dismissed during search to avoid clutter.
//
//  The pill is draggable: it rests bottom-trailing and the user can park it
//  anywhere over the transcript. The parked spot is the setting — it persists
//  in AppStorage and applies to every episode.
//

import SwiftUI

struct JumpToPlayingPill: View {
    var isVisible: Bool
    var action: () -> Void

    /// Parked position, as a negative inset from the bottom-trailing corner.
    @AppStorage("jumpToPlayingOffsetX") private var parkedX: Double = 0
    @AppStorage("jumpToPlayingOffsetY") private var parkedY: Double = 0

    @State private var dragTranslation: CGSize = .zero
    @State private var pillSize: CGSize = .zero

    @Environment(\.appAccentColor) private var accent
    @Environment(\.colorScheme) private var colorScheme

    private static let edgeInset: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let offset = clamped(
                CGSize(width: parkedX + dragTranslation.width,
                       height: parkedY + dragTranslation.height),
                in: geo.size
            )
            Group {
                if isVisible {
                    pill
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { pillSize = $0 }
                        // High priority, not simultaneous: the 8pt slop keeps a
                        // plain tap flowing to the Button, while a real drag
                        // wins before the ScrollView starts panning.
                        .highPriorityGesture(dragGesture(in: geo.size))
                        .offset(offset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .animation(.snappy(duration: 0.25), value: isVisible)
        }
    }

    private var pill: some View {
        let fill = AccentFill.color(accent, colorScheme)
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.subheadline.weight(.semibold))
                Text("Jump to playing")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            // One material, tinted — not glass painted over a separate
            // `.tint` fill. Two of them fight: the glass washes the
            // fill out, and the label was hardcoded `.white`, so the
            // pill read as white text on pale glass in light mode and
            // white on white in dark.
            .foregroundStyle(fill.contrastingLabel)
            .glassEffect(Glass.regular.tint(fill), in: .capsule)
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Self.edgeInset)
        .padding(.bottom, Self.edgeInset)
        .accessibilityLabel("Jump to currently playing sentence")
    }

    private func dragGesture(in container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { dragTranslation = $0.translation }
            .onEnded { value in
                let parked = clamped(
                    CGSize(width: parkedX + value.translation.width,
                           height: parkedY + value.translation.height),
                    in: container
                )
                parkedX = parked.width
                parkedY = parked.height
                dragTranslation = .zero
            }
    }

    /// Keeps the pill inside its container. Zero is the resting bottom-trailing
    /// corner, so both axes only ever travel negative.
    private func clamped(_ offset: CGSize, in container: CGSize) -> CGSize {
        let minX = -max(container.width - pillSize.width, 0)
        let minY = -max(container.height - pillSize.height, 0)
        return CGSize(width: min(max(offset.width, minX), 0),
                      height: min(max(offset.height, minY), 0))
    }
}
