import SwiftUI

struct TranscriptFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: ExpandedPlayerViewModel

    @AppStorage("skipForwardInterval") private var skipForwardInterval: Int = 30
    @AppStorage("skipBackwardInterval") private var skipBackwardInterval: Int = 15

    private var toolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .confirmationAction
        #endif
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                miniPlayerBar
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                Divider()

                FullTranscriptContent(
                    sentences: viewModel.groupedSentences,
                    currentTime: viewModel.isPlaying ? viewModel.currentTime : nil,
                    searchQuery: $viewModel.transcriptSearchQuery,
                    onSegmentTap: viewModel.seekToSegment
                )
            }
            .navigationTitle("Transcript")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: toolbarPlacement) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private var miniPlayerBar: some View {
        HStack(spacing: 12) {
            if let imageURL = viewModel.imageURL {
                CachedAsyncImage(url: imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.episodeTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(viewModel.currentTimeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 16) {
                Button(action: viewModel.skipBackward) {
                    Image(systemName: "gobackward.\(skipBackwardInterval)")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Skip back \(skipBackwardInterval) seconds")

                Button(action: viewModel.togglePlayPause) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

                Button(action: viewModel.skipForward) {
                    Image(systemName: "goforward.\(skipForwardInterval)")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Skip forward \(skipForwardInterval) seconds")
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }
}
