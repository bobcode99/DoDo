//
//  MacEpisodeTranscriptView.swift
//  PodcastAnalyzer
//
//  Standalone Transcript page on macOS. Pushed from MacEpisodeDetailView via
//  EpisodeTranscriptRoute. Reuses EpisodeTranscriptView verbatim with a small
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
            EpisodeTranscriptView(
                viewModel: viewModel,
                onShowTranslationPicker: { showTranslationLanguagePicker = true },
                onShowSubtitleSettings: { showSubtitleSettings = true },
                onShowRegenerateConfirmation: { showRegenerateConfirmation = true }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Transcript")
        .navigationSubtitle(viewModel.title)
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
