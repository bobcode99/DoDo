import SwiftUI

/// A circular progress indicator for translation status. No text inside:
/// at chip size any count truncates, so callers with room show it beside.
struct TranslationProgressCircle: View {
    let status: TranslationStatus

    var body: some View {
        if case .translating(let progress, _, _) = status {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.2), value: progress)
            }
        } else {
            ProgressView()
                .controlSize(.mini)
        }
    }
}
