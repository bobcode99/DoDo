import SwiftUI

/// Shared trailing-toolbar content for `EpisodeDetailView` (iOS) and
/// `MacEpisodeDetailView` (macOS): translate button (hidden on the AI tab)
/// plus the episode's More actions.
struct EpisodeDetailToolbarItems: ToolbarContent {
    let viewModel: EpisodeDetailViewModel
    var selectedTab: Int
    @Binding var showTranslationLanguagePicker: Bool
    @Binding var showDeleteConfirmation: Bool

    var body: some ToolbarContent {
        if selectedTab != 2 {
            ToolbarItem(placement: Self.placement) {
                TranslateButton(viewModel: viewModel, showPicker: $showTranslationLanguagePicker)
            }
        }
        #if os(iOS)
        if #available(iOS 27, *) {
            // The system's own overflow (•••) — standard glyph, placement and
            // VoiceOver label instead of a hand-rolled Menu.
            ToolbarOverflowMenu { moreActions }
        } else {
            moreMenu
        }
        #else
        moreMenu
        #endif
    }

    /// Pre-iOS 27 (and macOS) stand-in for `ToolbarOverflowMenu`.
    private var moreMenu: some ToolbarContent {
        ToolbarItem(placement: Self.placement) {
            Menu {
                moreActions
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More options")
        }
    }

    private var moreActions: some View {
        MoreActions(viewModel: viewModel, showDeleteConfirmation: $showDeleteConfirmation)
    }

    private static var placement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

/// Views, not inline toolbar content, so reads of the observable view model
/// are tracked the usual way and the menu/label stay current.
private struct MoreActions: View {
    let viewModel: EpisodeDetailViewModel
    @Binding var showDeleteConfirmation: Bool

    var body: some View {
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
    }
}

private struct TranslateButton: View {
    let viewModel: EpisodeDetailViewModel
    @Binding var showPicker: Bool

    var body: some View {
        if viewModel.translation.translationStatus.isTranslating {
            Menu {
                Button("Stop Translating", systemImage: "stop.circle", role: .destructive) {
                    viewModel.translation.stopTranscriptTranslation()
                }
            } label: {
                translateButtonLabel
            }
            .accessibilityLabel(translateAccessibilityLabel)
        } else {
            Button {
                showPicker = true
            } label: {
                translateButtonLabel
            }
            .accessibilityLabel(translateAccessibilityLabel)
        }
    }

    // MARK: - Translate Button Status

    @ViewBuilder
    private var translateButtonLabel: some View {
        if viewModel.translation.translationStatus.isTranslating {
            TranslationProgressCircle(status: viewModel.translation.translationStatus)
                .frame(width: 24, height: 24)
        } else if case .failed = viewModel.translation.translationStatus {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.translation.hasExistingTranslation {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "translate.fill")
                    .foregroundStyle(.blue)
                if let lang = viewModel.translation.selectedTranslationLanguage {
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

    // LocalizedStringKey, not String: a String label skips the catalog.
    private var translateAccessibilityLabel: LocalizedStringKey {
        if viewModel.translation.translationStatus.isTranslating { return "Translating in progress" }
        if case .failed = viewModel.translation.translationStatus { return "Translation failed" }
        if viewModel.translation.hasExistingTranslation,
           let lang = viewModel.translation.selectedTranslationLanguage {
            return "Translated to \(lang.displayName). Change language."
        }
        return "Translate"
    }
}
