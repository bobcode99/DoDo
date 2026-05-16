import SwiftUI

/// Bubble shown when a user taps a timestamp link inside a description or
/// transcript. Offers "Play from …" and "Share…" actions.
struct TimestampPopup: View {
    let seconds: TimeInterval
    let onPlay: () -> Void
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onPlay) {
                Label("Play from \(TimestampUtils.formatSeconds(seconds))", systemImage: "play.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
            }
            Divider().padding(.leading, 16)
            Button(action: onShare) {
                Label("Share...", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
            }
        }
        .font(.body)
        .foregroundStyle(.primary)
        .frame(width: 240)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
    }
}
