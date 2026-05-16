import SwiftUI

/// Shared trailing-toolbar content for `EpisodeDetailView` (iOS) and
/// `MacEpisodeDetailView` (macOS): translate button (hidden on the AI tab)
/// plus a More menu.
struct EpisodeDetailToolbarItems: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    var selectedTab: Int
    @Binding var showTranslationLanguagePicker: Bool
    @Binding var showDeleteConfirmation: Bool

    var body: some View {
        HStack(spacing: 16) {
            if selectedTab != 2 {
                Button {
                    showTranslationLanguagePicker = true
                } label: {
                    Image(systemName: "translate")
                }
                .accessibilityLabel("Translate")
            }
            Menu {
                EpisodeMenuActions(
                    isStarred: viewModel.isStarred,
                    isCompleted: viewModel.isCompleted,
                    hasLocalAudio: viewModel.hasLocalAudio,
                    downloadState: viewModel.downloadState,
                    audioURL: viewModel.audioURL,
                    onToggleStar: { viewModel.toggleStar() },
                    onTogglePlayed: { viewModel.togglePlayed() },
                    onDownload: { viewModel.startDownload() },
                    onCancelDownload: { viewModel.cancelDownload() },
                    onDeleteDownload: { showDeleteConfirmation = true },
                    onShare: { viewModel.shareEpisode() },
                    onPlayNext: { viewModel.addToPlayNext() }
                )
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More options")
        }
    }
}
