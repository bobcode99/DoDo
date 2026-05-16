//
//  MacEpisodeAIAnalysisView.swift
//  PodcastAnalyzer
//
//  Standalone AI Analysis page on macOS. Pushed from MacEpisodeDetailView via
//  EpisodeAIAnalysisRoute. Reuses EpisodeAIAnalysisView verbatim with a small
//  EpisodeMiniHeader on top for context.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacEpisodeAIAnalysisView: View {
    @State private var viewModel: EpisodeDetailViewModel

    // Sheets / alerts state.
    @State private var showDeleteConfirmation = false
    @State private var showSubtitleSettings = false
    @State private var showTranslationLanguagePicker = false
    @State private var showRegenerateConfirmation = false

    // Scroll bindings required by EpisodeAIAnalysisView. As with the
    // Transcript page, the collapsing header is iOS-only — these stay at
    // their defaults on macOS.
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
            EpisodeAIAnalysisView(
                viewModel: viewModel,
                embedsOwnScroll: true,
                isHeaderVisible: $isHeaderVisible,
                lastScrollOffset: $lastScrollOffset,
                isUserScrolling: $isUserScrolling,
                scrollToTopTrigger: $scrollToTopTrigger
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("AI Analysis")
        .navigationSubtitle(viewModel.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EpisodeDetailToolbarItems(
                    viewModel: viewModel,
                    selectedTab: 2, // AI tab — translate button is hidden
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
