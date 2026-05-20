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
                    translateButtonLabel
                }
                .disabled(viewModel.translationStatus.isTranslating)
                .accessibilityLabel(translateAccessibilityLabel)
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

    // MARK: - Translate Button Status

    @ViewBuilder
    private var translateButtonLabel: some View {
        if viewModel.translationStatus.isTranslating {
            TranslationProgressCircle(status: viewModel.translationStatus)
                .frame(width: 24, height: 24)
        } else if case .failed = viewModel.translationStatus {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.hasExistingTranslation {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "translate.fill")
                    .foregroundStyle(.blue)
                if let lang = viewModel.selectedTranslationLanguage {
                    Text(lang.shortName)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(.blue, in: .capsule)
                        .foregroundStyle(.white)
                        .offset(x: 4, y: 4)
                }
            }
        } else {
            Image(systemName: "translate")
        }
    }

    private var translateAccessibilityLabel: String {
        if viewModel.translationStatus.isTranslating { return "Translating in progress" }
        if case .failed = viewModel.translationStatus { return "Translation failed" }
        if viewModel.hasExistingTranslation,
           let lang = viewModel.selectedTranslationLanguage {
            return "Translated to \(lang.displayName). Change language."
        }
        return "Translate"
    }
}
