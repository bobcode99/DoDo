//
//  TranscriptContentView.swift
//  PodcastAnalyzer
//
//  Transcript tab content. Reads audio progress directly from the @Observable
//  EnhancedAudioManager — no in-view polling timer, no local cached time.
//  A single proxy.scrollTo on activeSentenceID drives auto-scroll.
//

import SwiftUI

struct TranscriptContentView: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    @Binding var isHeaderVisible: Bool
    @Binding var lastScrollOffset: CGFloat
    @Binding var isUserScrolling: Bool
    @Binding var scrollToTopTrigger: Bool

    var onShowTranslationPicker: () -> Void
    var onShowSubtitleSettings: () -> Void
    var onShowRegenerateConfirmation: () -> Void

    @State private var autoScrollEnabled = true

    /// Local binding for RSSTranscriptWarningBanner — onChange bridges to callback.
    @State private var showRegenerateConfirmation = false

    /// Drives the dedicated search sheet.
    @State private var showSearchSheet = false

    /// Current audio time when this episode is loaded; nil when it isn't.
    /// Reading audioManager.currentTime here registers @Observable observation,
    /// so the view re-evaluates as playback advances.
    private var currentTime: TimeInterval? {
        viewModel.isCurrentEpisode ? viewModel.audioManager.currentTime : nil
    }

    /// The sentence that should be highlighted (last-started semantics).
    private var activeSentenceID: Int? {
        guard let time = currentTime else { return nil }
        return viewModel.transcriptSentences.last { $0.startTime <= time }?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            TranscriptToolbar(
                viewModel: viewModel,
                autoScrollEnabled: $autoScrollEnabled,
                onShowSearch: { showSearchSheet = true },
                onShowTranslationPicker: onShowTranslationPicker,
                onShowSubtitleSettings: onShowSubtitleSettings,
                onShowRegenerateOptions: onShowRegenerateConfirmation
            )
            Divider()

            if viewModel.transcriptSource == "rss" && viewModel.hasTranscript {
                RSSTranscriptWarningBanner(
                    showRegenerateConfirmation: $showRegenerateConfirmation,
                    hasLocalAudio: viewModel.hasLocalAudio
                )
            }

            if viewModel.hasTranscript && !viewModel.isTranscriptProcessing {
                transcriptScrollContent
            } else {
                transcriptStatusSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: showRegenerateConfirmation) { _, isShowing in
            if isShowing {
                onShowRegenerateConfirmation()
                showRegenerateConfirmation = false
            }
        }
        .onChange(of: viewModel.transcriptSearchQuery) { _, newQuery in
            viewModel.updateSearchMatches(query: newQuery)
        }
        .sheet(isPresented: $showSearchSheet) {
            TranscriptSearchSheet(viewModel: viewModel) { _ in }
        }
    }

    // MARK: - Scroll Content

    private var transcriptScrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    Color.clear.frame(height: 0).id("transcriptTop")

                    SentenceBasedTranscriptView(
                        sentences: viewModel.transcriptSentences,
                        currentTime: currentTime,
                        searchQuery: viewModel.transcriptSearchQuery,
                        onSegmentTap: viewModel.seekToSegment,
                        subtitleMode: viewModel.effectiveDisplayMode,
                        searchMatchIds: Set(viewModel.searchMatchIds),
                        currentSearchMatchId: viewModel.searchMatchIds.isEmpty
                            ? nil
                            : viewModel.searchMatchIds[viewModel.currentMatchIndex]
                    )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .trackScrollForHeaderCollapse(
                isHeaderVisible: $isHeaderVisible,
                lastOffset: $lastScrollOffset,
                isUserScrolling: isUserScrolling
            )
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .interacting { autoScrollEnabled = false }
                isUserScrolling = newPhase == .interacting || newPhase == .decelerating
            }
            .onChange(of: activeSentenceID) { _, newID in
                guard autoScrollEnabled,
                      let id = newID,
                      viewModel.transcriptSearchQuery.isEmpty else { return }
                withAnimation(.spring(duration: 0.5, bounce: 0.1)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: viewModel.currentMatchIndex) { _, _ in
                guard !viewModel.searchMatchIds.isEmpty else { return }
                let matchId = viewModel.searchMatchIds[viewModel.currentMatchIndex]
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(matchId, anchor: .center)
                }
            }
            .onChange(of: scrollToTopTrigger) { _, _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("transcriptTop", anchor: .top)
                }
                isHeaderVisible = true
            }
        }
    }

    // MARK: - Status Section

    @ViewBuilder
    private var transcriptStatusSection: some View {
        EpisodeTranscriptStatusView(viewModel: viewModel)
            .frame(maxWidth: .infinity)
            .padding()
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .padding(.horizontal)
    }
}
