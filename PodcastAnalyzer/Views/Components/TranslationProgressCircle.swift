import SwiftUI

/// A circular progress indicator for translation status.
struct TranslationProgressCircle: View {
    let status: TranslationStatus

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 3)

            if case .translating(let progress, let completed, _) = status {
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.2), value: progress)

                Text("\(completed)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.blue)
            } else if case .preparingSession = status {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}
