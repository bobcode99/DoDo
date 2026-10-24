import SwiftUI

struct EpisodeDownloadButton: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            switch viewModel.downloadState {
            case .notDownloaded:
                Button(action: { viewModel.startDownload() }) {
                    Label("Download", systemImage: "arrow.down.circle")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(Color.gray)
                        .clipShape(.capsule)
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
                    .frame(minHeight: 44)
                    .background(Color.orange)
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel Download")

            case .finishing:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(Color.blue)
                .clipShape(.capsule)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Downloading")

            case .downloaded:
                Button(action: { showDeleteConfirmation = true }) {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(Color.green)
                        .clipShape(.capsule)
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
                    Label("Retry", systemImage: "exclamationmark.circle")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .background(Color.red)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
