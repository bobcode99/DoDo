//
//  EpisodeDetailView.swift
//  PodcastAnalyzer
//
//  iOS episode detail. Collapses the header on scroll, reserves 80pt at the
//  bottom for the mini player. Shared tab / toolbar / sheets are in
//  `Views/Components/EpisodeDetail*`. The macOS counterpart lives in
//  `MacEpisodeDetailView.swift` — and is aliased here so shared iOS-leaning
//  files (HomeView, SearchView, etc.) keep compiling on macOS even though
//  they are never displayed there at runtime.
//

import SwiftData
#if os(macOS)
typealias EpisodeDetailView = MacEpisodeDetailView
#endif

#if os(iOS)
import SwiftUI

struct EpisodeDetailView: View {
    @State private var viewModel: EpisodeDetailViewModel

    @State private var selectedTab = 0
    @State private var showDeleteConfirmation = false
    @State private var showSubtitleSettings = false
    @State private var showTranslationLanguagePicker = false
    @State private var showRegenerateConfirmation = false

    // Header collapse state
    @State private var isHeaderVisible: Bool = true
    @State private var lastScrollOffset: CGFloat = 0
    @State private var isUserScrolling: Bool = false

    // Scroll-to-top trigger
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
            EpisodeDetailHeaderView(viewModel: viewModel)
                .frame(height: isHeaderVisible ? nil : 0)
                .clipped()
                .opacity(isHeaderVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isHeaderVisible)
            Divider()
                .opacity(isHeaderVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isHeaderVisible)
            EpisodeDetailTabsContent(
                viewModel: viewModel,
                selectedTab: $selectedTab,
                isHeaderVisible: $isHeaderVisible,
                lastScrollOffset: $lastScrollOffset,
                isUserScrolling: $isUserScrolling,
                scrollToTopTrigger: $scrollToTopTrigger,
                enableScrollHeaderCollapse: true,
                onShowTranslationLanguagePicker: { showTranslationLanguagePicker = true },
                onShowSubtitleSettings: { showSubtitleSettings = true },
                onShowRegenerateConfirmation: { showRegenerateConfirmation = true }
            )
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EpisodeDetailToolbarItems(
                    viewModel: viewModel,
                    selectedTab: selectedTab,
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
