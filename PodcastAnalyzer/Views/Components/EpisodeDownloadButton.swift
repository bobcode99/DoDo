
import SwiftUI

struct EpisodeDownloadButton: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            switch viewModel.downloadState {
            case .notDownloaded:
                Button(action: { viewModel.startDownload() }) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.gray)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

            case .downloading:
                // Live ring polls in-flight progress itself — the computed
                // downloadState only refreshes on state transitions, so a
                // static ring here would freeze at 0%.
                Button(action: { viewModel.cancelDownload() }) {
                    LiveDownloadProgressRing(
                        episodeTitle: viewModel.episode.title,
                        podcastTitle: viewModel.podcastTitle,
                        size: 16,
                        color: .white,
                        symbol: "xmark"
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

            case .finishing:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.blue)
                .clipShape(Capsule())

            case .downloaded:
                Button(action: { showDeleteConfirmation = true }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.green)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Delete Download",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        viewModel.deleteDownload()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "Are you sure you want to delete this downloaded episode? You can download it again later."
                    )
                }

            case .failed:
                Button(action: { viewModel.startDownload() }) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
