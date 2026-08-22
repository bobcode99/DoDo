//
//  MacEpisodeDetailView.swift
//  PodcastAnalyzer
//
//  Summary-only landing page for an episode on macOS.
//
//  Tapping an episode opens this view. From here the user navigates to
//  separate pages for Transcript (MacEpisodeTranscriptView) and AI Analysis
//  (MacEpisodeAIAnalysisView). The three pages are independent NavigationStack
//  destinations so they don't share a single ScrollView / layout — fixing the
//  long-content layout regressions that came with the previous tab approach.
//

#if os(macOS)
import SwiftData
import SwiftUI

struct MacEpisodeDetailView: View {
    @State private var viewModel: EpisodeDetailViewModel

    // Sheets / alerts state — driven by the shared modifier.
    @State private var showDeleteConfirmation = false
    @State private var showSubtitleSettings = false
    @State private var showTranslationLanguagePicker = false
    @State private var showRegenerateConfirmation = false

    // Inline timestamp tap handling (description timestamp links).
    @State private var tappedTimestampSeconds: TimeInterval?
    @State private var timestampTapX: CGFloat = 0
    @State private var timestampTapY: CGFloat = 200

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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EpisodeDetailHeaderView(viewModel: viewModel)

                actionButtons

                Divider()

                EpisodeSummaryView(
                    viewModel: viewModel,
                    tappedTimestampSeconds: $tappedTimestampSeconds
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded {
                    timestampTapX = $0.location.x
                    timestampTapY = $0.location.y
                }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .timestampPopup(
            viewModel: viewModel,
            tappedSeconds: $tappedTimestampSeconds,
            tapX: timestampTapX,
            tapY: timestampTapY
        )
        .navigationTitle(viewModel.title)
        .navigationSubtitle(viewModel.podcastTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EpisodeDetailToolbarItems(
                    viewModel: viewModel,
                    selectedTab: 0, // Summary — translate button is shown (acts on description)
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

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            NavigationLink(
                value: EpisodeTranscriptRoute(
                    episode: viewModel.episode,
                    podcastTitle: viewModel.podcastTitle,
                    fallbackImageURL: viewModel.imageURLString,
                    podcastLanguage: viewModel.podcastLanguage
                )
            ) {
                Label("Transcript", systemImage: "captions.bubble")
            }
            .buttonStyle(.accentProminent)
            .controlSize(.large)
            .accessibilityHint("Open the transcript for this episode")

            NavigationLink(
                value: EpisodeAIAnalysisRoute(
                    episode: viewModel.episode,
                    podcastTitle: viewModel.podcastTitle,
                    fallbackImageURL: viewModel.imageURLString,
                    podcastLanguage: viewModel.podcastLanguage
                )
            ) {
                Label("AI Analysis", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Open the AI analysis for this episode")

            Spacer()
        }
        .padding(.horizontal, 24)
    }

}

#endif
