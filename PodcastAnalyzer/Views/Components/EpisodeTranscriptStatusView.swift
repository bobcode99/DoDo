import SwiftUI

/// Routes the episode's transcript state to the right sub-view. The heavy config
/// and generating UIs live in their own files (TranscriptGenerateConfigView /
/// TranscriptGeneratingView) so this stays a thin dispatcher.
struct EpisodeTranscriptStatusView: View {
    @Bindable var viewModel: EpisodeDetailViewModel

    var body: some View {
        switch viewModel.transcript.transcriptState {
        case .idle:
            idleView
        case .downloadingModel(let progress):
            generating(isModelDownload: true, progress: progress)
        case .transcribing(let progress):
            generating(isModelDownload: false, progress: progress)
        case .completed:
            completedView
        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - Idle

    @ViewBuilder
    private var idleView: some View {
        if viewModel.transcript.hasRSSTranscriptAvailable {
            rssAvailableView
        } else if viewModel.transcript.isDownloadingRSSTranscript {
            rssDownloadingView
        } else {
            TranscriptGenerateConfigView(viewModel: viewModel)
        }
    }

    private var rssAvailableView: some View {
        ContentUnavailableView {
            Label("Transcript Available", systemImage: "captions.bubble")
        } description: {
            Text("This episode has a transcript from the podcast feed.")
        } actions: {
            Button {
                viewModel.transcript.downloadRSSTranscript()
            } label: {
                Label("Download Transcript", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var rssDownloadingView: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Downloading Transcript")
                    .font(.headline)
            }
        } description: {
            Text("Fetching the transcript from the podcast feed.")
        }
    }

    // MARK: - Generating

    private func generating(isModelDownload: Bool, progress: Double) -> some View {
        TranscriptGeneratingView(
            engine: viewModel.transcript.effectiveEngine,
            languageName: viewModel.transcript.transcriptLanguageName,
            isModelDownload: isModelDownload,
            progress: progress,
            partProgress: viewModel.transcript.transcriptPartProgress,
            onCancel: { viewModel.transcript.cancelTranscript() }
        )
    }

    // MARK: - Completed

    private var completedView: some View {
        ContentUnavailableView {
            Label("Transcript Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } description: {
            Text("Tap a sentence to seek playback.")
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Transcription Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } description: {
            Text(message)
        } actions: {
            Button {
                viewModel.transcript.transcriptState = .idle
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }
}
