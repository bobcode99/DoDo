import SwiftUI

struct PlayerBottomActionsView: View {
    let queueCount: Int
    let onNavigateToEpisodeDetail: () -> Void
    let onOpenQueue: () -> Void

    var body: some View {
        HStack {
            AirPlayButton()
                .frame(width: 44, height: 44)

            Spacer()

            Button(action: onNavigateToEpisodeDetail) {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                    Text("Detail")
                }
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }

            Spacer()

            Button(action: onOpenQueue) {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                    if queueCount > 0 {
                        Text("\(queueCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                .contentShape(.rect)
            }
            .accessibilityLabel(queueCount > 0 ? "Queue, \(queueCount) items" : "Queue")
        }
        .padding(.horizontal, 32)
    }
}
