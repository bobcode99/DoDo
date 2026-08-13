import SwiftUI

#if os(iOS)
import UIKit
#endif

struct SmoothScrubber: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let isDurationLoading: Bool
    let onSeek: (Double) -> Void

    @State private var scrubTime: TimeInterval = 0
    @State private var isInteracting = false
    // Target written by the user's last seek. While set, ignore stale
    // currentTime updates from the periodic time observer (which can briefly
    // report the pre-seek position before the seek lands), so the thumb
    // doesn't snap back to the old spot and then jump to the new one.
    @State private var pendingSeekTarget: TimeInterval?

    private var effectiveDuration: TimeInterval { max(duration, 0.001) }

    var body: some View {
        VStack(spacing: 8) {
            scrubberSlider
                .tint(.primary)
                .scaleEffect(x: isInteracting ? 1.01 : 1.0, y: 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isInteracting)
                .sensoryFeedback(.impact(weight: .light), trigger: isInteracting)
                .disabled(isDurationLoading)
                .opacity(isDurationLoading ? 0.5 : 1.0)
                .onChange(of: currentTime) {
                    guard !isInteracting else { return }
                    if let target = pendingSeekTarget {
                        // Wait until the player time gets close to where we seeked.
                        // Anything further away is a stale observer tick — ignore it.
                        if abs(currentTime - target) < 0.75 {
                            pendingSeekTarget = nil
                            scrubTime = currentTime
                        }
                        return
                    }
                    scrubTime = currentTime
                }
                .onAppear {
                    scrubTime = currentTime
                }

            let displayTime = isInteracting ? scrubTime : currentTime
            HStack {
                Text(Formatters.formatPlaybackTime(displayTime))
                Spacer()
                Text("-" + Formatters.formatPlaybackTime(effectiveDuration - displayTime))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(isInteracting ? .primary : .secondary)
            .padding(.top, isInteracting ? 4 : 0)
            .animation(.easeOut(duration: 0.15), value: isInteracting)
        }
    }

    @ViewBuilder
    private var scrubberSlider: some View {
        #if os(iOS)
        ThumblessSlider(
            value: $scrubTime,
            range: 0...effectiveDuration,
            onEditingChanged: handleEditingChanged
        )
        #else
        Slider(
            value: $scrubTime,
            in: 0...effectiveDuration,
            onEditingChanged: handleEditingChanged
        )
        #endif
    }

    private func handleEditingChanged(_ editing: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isInteracting = editing
        }
        if editing {
            // User grabbed the slider — drop any pending seek guard so the
            // next release isn't gated by an obsolete target.
            pendingSeekTarget = nil
        } else {
            let target = scrubTime
            pendingSeekTarget = target
            onSeek(target / effectiveDuration)
            // Safety valve: if the seek never lands near the target (clamped
            // seek, or the episode advanced), drop the guard so the thumb
            // doesn't stay frozen at a position the player left behind.
            Task {
                try? await Task.sleep(for: .seconds(2))
                if pendingSeekTarget == target { pendingSeekTarget = nil }
            }
        }
    }
}

#if os(iOS)
/// Tap-anywhere scrubber.
///
/// Built on `DragGesture(minimumDistance: 0)` rather than a `UISlider`. That
/// gesture delivers `onChanged` on touch-down and `onEnded` on lift for a tap
/// and a drag alike, so "click to seek" and "drag to seek" are literally the
/// same code path — a tap cannot silently do nothing.
///
/// UIKit control tracking gave no such guarantee here: the player content sits
/// in a `ScrollView`, and `UIScrollView` delays content touches and can claim
/// them for its pan, so a quick tap on a `UISlider` may never complete a
/// begin/end tracking cycle and never commit a seek.
private struct ThumblessSlider: View {
    @Binding var value: TimeInterval
    let range: ClosedRange<TimeInterval>
    let onEditingChanged: (Bool) -> Void

    /// Finger is down. Drives the visual expand only — never the value.
    @State private var isTouching = false
    /// Set once the finger has actually travelled far enough to count as a
    /// scrub. `startValue` is the position at that moment and `originShift` the
    /// translation already accumulated, so the playhead picks up exactly where
    /// it was instead of hopping by the activation threshold.
    @State private var scrub: (startValue: TimeInterval, originShift: CGFloat)?

    /// Travel before a touch becomes a scrub. Below this it stays a tap, and a
    /// tap must never move the playhead.
    private let activationDistance: CGFloat = 2

    private let trackHeight: CGFloat = 4
    private let activeTrackHeight: CGFloat = 8
    private let thumbDiameter: CGFloat = 12
    private let activeThumbDiameter: CGFloat = 16
    /// The track is only a few points tall; give it a finger-sized row to land in.
    private let rowHeight: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let thumb = isTouching ? activeThumbDiameter : thumbDiameter
            let track = isTouching ? activeTrackHeight : trackHeight
            let centerX = thumb / 2 + max(width - thumb, 1) * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(height: track)

                Capsule()
                    .fill(Color.primary)
                    .frame(width: centerX, height: track)

                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .offset(x: centerX - thumb / 2)
            }
            .animation(.easeOut(duration: 0.15), value: isTouching)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            // The whole 44pt row is the target, not just the 4pt track.
            .contentShape(Rectangle())
            .gesture(
                // `minimumDistance: 0` so the bar can thicken the instant the
                // finger lands, the way Apple Podcasts does. The value is still
                // gated behind `activationDistance` below, so touching alone
                // changes nothing.
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isTouching = true
                        let dx = gesture.translation.width

                        if scrub == nil {
                            // Grab, don't jump: a touch anywhere on the bar
                            // picks the playhead up from where it already is.
                            // Seeking to the touch point would mean any stray
                            // contact destroys your position, with no undo.
                            guard abs(dx) > activationDistance else { return }
                            scrub = (value, dx)
                            onEditingChanged(true)
                        }
                        guard let scrub else { return }

                        let usable = max(width - thumb, 1)
                        let span = range.upperBound - range.lowerBound
                        let travelled = Double((dx - scrub.originShift) / usable) * span
                        value = min(max(scrub.startValue + travelled, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        isTouching = false
                        // Never activated => this was a tap. Leave the playhead
                        // alone and, crucially, do not report an edit: the
                        // parent commits a seek on every `false`.
                        guard scrub != nil else { return }
                        scrub = nil
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: rowHeight)
        // Replacing UISlider loses its VoiceOver semantics, so restate them.
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(Formatters.formatPlaybackTime(value))
        .accessibilityAdjustableAction { direction in
            let span = range.upperBound - range.lowerBound
            let step = max(span / 20, 1)
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: return
            }
            onEditingChanged(false)
        }
    }

    /// 0...1 position of `value` within `range`.
    private var progress: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - range.lowerBound) / span, 0), 1))
    }
}
#endif
