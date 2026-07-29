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
        // The track is only a couple of points tall; give it a finger-sized
        // row to land in (UISlider centers the track in its bounds).
        .frame(height: 44)
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
private struct ThumblessSlider: UIViewRepresentable {
    @Binding var value: TimeInterval
    let range: ClosedRange<TimeInterval>
    let onEditingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> UISlider {
        let slider = TrackTapSlider()
        slider.setThumbImage(Self.thumbImage(diameter: 12), for: .normal)
        slider.setThumbImage(Self.thumbImage(diameter: 16), for: .highlighted)
        slider.minimumTrackTintColor = .label
        slider.maximumTrackTintColor = UIColor.label.withAlphaComponent(0.18)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchDown(_:)),
            for: .touchDown
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchUp(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        return slider
    }

    func updateUIView(_ uiView: UISlider, context: Context) {
        uiView.minimumValue = Float(range.lowerBound)
        uiView.maximumValue = Float(range.upperBound)
        if !context.coordinator.isEditing {
            uiView.setValue(Float(value), animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, onEditingChanged: onEditingChanged)
    }

    /// White circular thumb with a soft drop shadow, matching the design's
    /// scrubber knob. Padded so the shadow isn't clipped by the thumb bounds.
    private static func thumbImage(diameter: CGFloat) -> UIImage {
        let pad: CGFloat = 3
        let size = CGSize(width: diameter + pad * 2, height: diameter + pad * 2)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            c.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 3,
                color: UIColor.black.withAlphaComponent(0.3).cgColor
            )
            c.setFillColor(UIColor.white.cgColor)
            c.fillEllipse(in: CGRect(x: pad, y: pad, width: diameter, height: diameter))
        }
    }

    /// UISlider only starts a drag when the touch lands on the thumb, which is
    /// a 12pt target on a full-width track — most grabs miss. This jumps the
    /// value to wherever the track was touched and drags on from there.
    private final class TrackTapSlider: UISlider {
        override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
            let track = trackRect(forBounds: bounds)
            let thumb = thumbRect(forBounds: bounds, trackRect: track, value: value)
            let point = touch.location(in: self)
            // Touch already on (or near) the thumb — keep UIKit's grab so the
            // thumb doesn't teleport under the finger.
            if !thumb.insetBy(dx: -16, dy: -16).contains(point) {
                let usable = track.width - thumb.width
                if usable > 0 {
                    let fraction = min(max((point.x - track.minX - thumb.width / 2) / usable, 0), 1)
                    value = minimumValue + Float(fraction) * (maximumValue - minimumValue)
                    sendActions(for: .valueChanged)
                }
            }
            return super.beginTracking(touch, with: event)
        }
    }

    final class Coordinator: NSObject {
        @Binding var value: TimeInterval
        let onEditingChanged: (Bool) -> Void
        var isEditing = false

        init(value: Binding<TimeInterval>, onEditingChanged: @escaping (Bool) -> Void) {
            self._value = value
            self.onEditingChanged = onEditingChanged
        }

        @objc func valueChanged(_ sender: UISlider) {
            value = TimeInterval(sender.value)
        }

        @objc func touchDown(_ sender: UISlider) {
            isEditing = true
            onEditingChanged(true)
        }

        @objc func touchUp(_ sender: UISlider) {
            isEditing = false
            onEditingChanged(false)
        }
    }
}
#endif
