//
//  EpisodeTranscriptPage.swift
//  PodcastAnalyzer
//
//  Standalone iOS page that hosts EpisodeTranscriptView. Pushed onto the
//  NavigationStack from EpisodeDetailView (summary landing) via
//  EpisodeTranscriptRoute. Owns its own EpisodeDetailViewModel + the four
//  sheet/alert flags consumed by `episodeDetailSheetsAndAlerts`.
//

#if os(iOS)
import SwiftData
import SwiftUI

struct EpisodeTranscriptPage: View {
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
        EpisodeTranscriptView(
            viewModel: viewModel,
            onShowTranslationPicker: { showTranslationLanguagePicker = true },
            onShowSubtitleSettings: { showSubtitleSettings = true },
            onShowRegenerateConfirmation: { showRegenerateConfirmation = true }
        )
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
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
