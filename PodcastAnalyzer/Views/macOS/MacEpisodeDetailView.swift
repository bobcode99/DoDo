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

                descriptionContent
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay { timestampPopupOverlay }
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
            .buttonStyle(.borderedProminent)
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

    // MARK: - Description

    @ViewBuilder
    private var descriptionContent: some View {
        if let translated = viewModel.translatedDescription {
            VStack(alignment: .leading, spacing: 12) {
                HTMLTextView(
                    attributedString: NSAttributedString(
                        TimestampUtils.attributedStringWithTimestampLinks(translated)
                    )
                )
                .textSelection(.enabled)

                Divider()

                DisclosureGroup("Original") {
                    descriptionView
                        .textSelection(.enabled)
                }
                .foregroundStyle(.secondary)
            }
        } else {
            descriptionView
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var descriptionView: some View {
        switch viewModel.descriptionContent {
        case .loading:
            Text("Loading...")
                .foregroundStyle(.secondary)
        case .empty:
            Text("No description available.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .parsed(let attributedString):
            HTMLTextView(attributedString: attributedString, linkTimestamps: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.openURL, OpenURLAction { url in
                    if let seconds = TimestampUtils.parseTimestampURL(url) {
                        tappedTimestampSeconds = seconds
                        return .handled
                    }
                    return .systemAction
                })
        }
    }

    // MARK: - Timestamp popup

    @ViewBuilder
    private var timestampPopupOverlay: some View {
        if let seconds = tappedTimestampSeconds {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { tappedTimestampSeconds = nil }
                .overlay {
                    GeometryReader { geo in
                        let popupWidth: CGFloat = 240
                        let popupHeight: CGFloat = 110
                        let x = min(
                            max(timestampTapX, popupWidth / 2 + 16),
                            geo.size.width - popupWidth / 2 - 16
                        )
                        let showAbove = timestampTapY > geo.size.height - popupHeight - 60
                        let y = showAbove
                            ? timestampTapY - popupHeight / 2 - 10
                            : timestampTapY + popupHeight / 2 + 10

                        TimestampPopup(
                            seconds: seconds,
                            onPlay: {
                                viewModel.seekToTime(seconds)
                                tappedTimestampSeconds = nil
                            },
                            onShare: {
                                viewModel.shareTimestampedLink(seconds: seconds)
                                tappedTimestampSeconds = nil
                            }
                        )
                        .position(x: x, y: y)
                        .transition(
                            .scale(scale: 0.88, anchor: showAbove ? .bottom : .top)
                            .combined(with: .opacity)
                        )
                    }
                }
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: tappedTimestampSeconds != nil)
        }
    }
}

#endif
