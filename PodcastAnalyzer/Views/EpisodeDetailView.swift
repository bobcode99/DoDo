//
//  EpisodeDetailView.swift
//  PodcastAnalyzer
//
//  iOS episode landing page. Shows the episode header, two action buttons
//  to push the Transcript and AI Analysis sub-pages, and the description
//  (summary). Mirrors the macOS pattern (MacEpisodeDetailView): each tab is
//  now an independent NavigationStack destination, not a shared tab host.
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

    // Header collapse state
    @State private var isHeaderVisible: Bool = true
    @State private var lastScrollOffset: CGFloat = 0
    @State private var isUserScrolling: Bool = false
    @State private var scrollToTopTrigger: Bool = false

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
        VStack(spacing: 0) {
            EpisodeDetailHeaderView(viewModel: viewModel)
                .frame(height: isHeaderVisible ? nil : 0)
                .clipped()
                .opacity(isHeaderVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isHeaderVisible)
            Divider()
                .opacity(isHeaderVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: isHeaderVisible)

            summaryScrollContent
                .overlay(alignment: .topTrailing) {
                    if !isHeaderVisible {
                        Button {
                            scrollToTopTrigger.toggle()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 32, height: 32)
                                .glassEffect(.regular, in: .circle)
                        }
                        .padding(.trailing, 12)
                        .padding(.top, 8)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .timestampPopup(
                    viewModel: viewModel,
                    tappedSeconds: $tappedTimestampSeconds,
                    tapX: timestampTapX,
                    tapY: timestampTapY
                )
                .animation(.easeInOut(duration: 0.25), value: isHeaderVisible)
        }
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

    // MARK: - Scrollable summary content

    private var summaryScrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Color.clear.frame(height: 0).id("summaryTop")

                VStack(alignment: .leading, spacing: 16) {
                    actionButtons

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
            .onScrollPhaseChange { _, newPhase in
                isUserScrolling = newPhase == .interacting || newPhase == .decelerating
            }
            .trackScrollForHeaderCollapse(
                isHeaderVisible: $isHeaderVisible,
                lastOffset: $lastScrollOffset,
                isUserScrolling: isUserScrolling
            )
            .onChange(of: scrollToTopTrigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("summaryTop", anchor: .top)
                }
                isHeaderVisible = true
            }
        }
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
        .padding(.horizontal)
    }
}

#endif
