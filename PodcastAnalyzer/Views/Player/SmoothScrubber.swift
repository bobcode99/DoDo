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

    private var effectiveDuration: TimeInterval { max(duration, 0.001) }

    var body: some View {
        VStack(spacing: 8) {
            scrubberSlider
                .tint(.primary)
                .scaleEffect(x: isInteracting ? 1.02 : 1.0, y: isInteracting ? 2.5 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isInteracting)
                .sensoryFeedback(.impact(weight: .light), trigger: isInteracting)
                .disabled(isDurationLoading)
                .opacity(isDurationLoading ? 0.5 : 1.0)
                .onChange(of: currentTime) {
                    guard !isInteracting else { return }
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
        if !editing {
            onSeek(scrubTime / effectiveDuration)
        }
    }
}

#if os(iOS)
private struct ThumblessSlider: UIViewRepresentable {
    @Binding var value: TimeInterval
    let range: ClosedRange<TimeInterval>
    let onEditingChanged: (Bool) -> Void

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.setThumbImage(UIImage(), for: .normal)
        slider.setThumbImage(UIImage(), for: .highlighted)
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
