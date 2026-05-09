import SwiftUI

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
            Slider(
                value: $scrubTime,
                in: 0...effectiveDuration,
                onEditingChanged: { editing in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isInteracting = editing
                    }
                    if !editing {
                        onSeek(scrubTime / effectiveDuration)
                    }
                }
            )
            .tint(.primary)
            .scaleEffect(x: isInteracting ? 1.02 : 1.0, y: isInteracting ? 2.5 : 1.0)
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
}
