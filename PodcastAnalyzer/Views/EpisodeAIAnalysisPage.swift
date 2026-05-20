//
//  EpisodeAIAnalysisPage.swift
//  PodcastAnalyzer
//
//  Standalone iOS page that hosts EpisodeAIAnalysisView. Pushed onto the
//  NavigationStack from EpisodeDetailView (summary landing) via
//  EpisodeAIAnalysisRoute. Owns its own EpisodeDetailViewModel + the sheet
//  flags consumed by `episodeDetailSheetsAndAlerts`.
//

#if os(iOS)
import SwiftData
import SwiftUI

struct EpisodeAIAnalysisPage: View {
    @State private var viewModel: EpisodeDetailViewModel

    @State private var showDeleteConfirmation = false
    @State private var showSubtitleSettings = false
    @State private var showTranslationLanguagePicker = false
    @State private var showRegenerateConfirmation = false

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
        EpisodeAIAnalysisView(viewModel: viewModel)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 80)
            }
            .navigationTitle("AI Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EpisodeDetailToolbarItems(
                        viewModel: viewModel,
                        selectedTab: 2, // AI — translate button hidden
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
