//
//  EpisodeDetailView.swift
//  PodcastAnalyzer
//
//  iOS episode landing page. Single ScrollView containing the episode
//  header, a merged action row (Play / Download / Transcript / AI Analysis),
//  and the episode summary — the header scrolls with the content.
//
//  Aliased to MacEpisodeDetailView on macOS so shared iOS-leaning files
//  (HomeView, SearchView, etc.) keep compiling on macOS even though they
//  are never displayed there at runtime.
//

import SwiftData
#if os(macOS)
typealias EpisodeDetailView = MacEpisodeDetailView
#endif

#if os(iOS)
import SwiftUI

struct EpisodeDetailView: View {
    @State private var viewModel: EpisodeDetailViewModel

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
            VStack(alignment: .leading, spacing: 16) {
                EpisodeDetailHeaderView(
                    viewModel: viewModel,
                    showsPlaybackButtons: false
                )

                actionRow
                    .padding(.horizontal)

                EpisodeSummaryView(
                    viewModel: viewModel,
                    tappedTimestampSeconds: $tappedTimestampSeconds
                )
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onEnded {
                    timestampTapX = $0.location.x
                    timestampTapY = $0.location.y
                }
        )
        .timestampPopup(
            viewModel: viewModel,
            tappedSeconds: $tappedTimestampSeconds,
            tapX: timestampTapX,
            tapY: timestampTapY
        )
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 80)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EpisodeDetailToolbarItems(
                    viewModel: viewModel,
                    selectedTab: 0, // Summary — translate button shown (acts on description)
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

    // MARK: - Action row (Play / Download / Transcript / AI Analysis)

    private var actionRow: some View {
        HStack(spacing: 10) {
            LivePlaybackButton(
                episodeTitle: viewModel.title,
                podcastTitle: viewModel.podcastTitle,
                duration: viewModel.savedDuration,
                formattedDuration: viewModel.formattedDuration,
                lastPlaybackPosition: viewModel.lastPlaybackPosition,
                playbackProgress: viewModel.playbackProgress,
                isCompleted: viewModel.isCompleted,
                onPlay: { viewModel.playAction() },
                style: .iconOnly,
                isDisabled: viewModel.isPlayDisabled
            )

            EpisodeDownloadButton(viewModel: viewModel)

            NavigationLink(
                value: EpisodeTranscriptRoute(
                    episode: viewModel.episode,
                    podcastTitle: viewModel.podcastTitle,
                    fallbackImageURL: viewModel.imageURLString,
                    podcastLanguage: viewModel.podcastLanguage
                )
            ) {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.purple)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Transcript")
            .accessibilityHint("Open the transcript for this episode")

            NavigationLink(
                value: EpisodeAIAnalysisRoute(
                    episode: viewModel.episode,
                    podcastTitle: viewModel.podcastTitle,
                    fallbackImageURL: viewModel.imageURLString,
                    podcastLanguage: viewModel.podcastLanguage
                )
            ) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("AI Analysis")
            .accessibilityHint("Open the AI analysis for this episode")

            Spacer(minLength: 0)
        }
    }
}

#endif
