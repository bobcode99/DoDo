//
//  MacEpisodeTranscriptView.swift
//  PodcastAnalyzer
//
//  Standalone Transcript page on macOS. Pushed from MacEpisodeDetailView via
//  EpisodeTranscriptRoute. Reuses TranscriptContentView verbatim with a small
//  EpisodeMiniHeader on top for context.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacEpisodeTranscriptView: View {
    @State private var viewModel: EpisodeDetailViewModel

    // Sheets / alerts state — driven by the shared modifier.
    @State private var showDeleteConfirmation = false
    @State private var showSubtitleSettings = false
    @State private var showTranslationLanguagePicker = false
    @State private var showRegenerateConfirmation = false

    // Scroll bindings required by TranscriptContentView. macOS has no
    // collapsing header so `isHeaderVisible` stays true and the other
    // values are unused but kept satisfied for the API.
    @State private var isHeaderVisible = true
    @State private var lastScrollOffset: CGFloat = 0
    @State private var isUserScrolling = false
    @State private var scrollToTopTrigger = false

    init(
        episode: PodcastEpisodeInfo,
        podcastTitle: String,
        fallbackImageURL: String?,
        podcastLanguage: String = "en"
    ) {
        _viewModel = State(
            initialValue: EpisodeDetailViewModel(
                episode: episode,
                podcastTitle: podcastTitle,
                fallbackImageURL: fallbackImageURL,
                podcastLanguage: podcastLanguage
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            EpisodeMiniHeader(viewModel: viewModel)
            Divider()
            TranscriptContentView(
                viewModel: viewModel,
                isHeaderVisible: $isHeaderVisible,
                lastScrollOffset: $lastScrollOffset,
                isUserScrolling: $isUserScrolling,
                scrollToTopTrigger: $scrollToTopTrigger,
                onShowTranslationPicker: { showTranslationLanguagePicker = true },
                onShowSubtitleSettings: { showSubtitleSettings = true },
                onShowRegenerateConfirmation: { showRegenerateConfirmation = true }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Transcript")
        .navigationSubtitle(viewModel.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EpisodeDetailToolbarItems(
                    viewModel: viewModel,
                    selectedTab: 1, // Transcript — translate button shows
                    showTranslationLanguagePicker: $showTranslationLanguagePicker,
                    showDeleteConfirmation: $showDeleteConfirmation
                )
            }
        }
        .episodeDetailSheetsAndAlerts(
            viewModel: viewModel,
            showDeleteConfirmation: $showDeleteConfirmation,
            showSubtitleSettings: $showSubtitleSettings,
            showRegenerateConfirmation: $showRegenerateConfirmation,
            showTranslationLanguagePicker: $showTranslationLanguagePicker
        )
    }
}

#endif
