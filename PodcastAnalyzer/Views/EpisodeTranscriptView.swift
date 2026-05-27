//
//  EpisodeTranscriptView.swift
//  PodcastAnalyzer
//
//  Standalone transcript page. Reads audio progress directly from the
//  @Observable EnhancedAudioManager — no in-view polling timer. A single
//  proxy.scrollTo(activeSentenceID) drives auto-scroll.
//
//  Composition:
//   • Nav-bar toolbar items (search, display mode, transcript actions) are
//     contributed via `.toolbar` so the host's translate + ellipsis menu
//     merge naturally.
//   • A slim TranscriptStatusStrip shows the reading language, auto-scroll
//     state, and live search match counts.
//   • The transcript ScrollView overlays a floating "Jump to playing" pill
//     that appears when the user pauses following while the episode plays.
//

import SwiftUI

struct EpisodeTranscriptView: View {
    @Bindable var viewModel: EpisodeDetailViewModel

    var onShowTranslationPicker: () -> Void
    var onShowSubtitleSettings: () -> Void
    var onShowRegenerateConfirmation: () -> Void

    @State private var autoScrollEnabled = true
    @State private var showRegenerateConfirmation = false
    @State private var showSearchSheet = false
    @State private var showCopySuccess = false

    /// Tracks the topmost visible sentence so the floating scrub-time pill can
    /// show its timestamp. Updated by `.scrollPosition(id:anchor:.top)`.
    @State private var topVisibleSentenceID: Int?

    /// Pill visibility — only true while the user is actively swiping or the
    /// scroll is decelerating. Returns to `false` on `.idle`.
    @State private var showScrollTimestamp = false

    /// Search query cached for the lifetime of this view so reopening the
    /// search sheet recalls the last text. Cleared on view deinit (it's
    /// @State on a per-push view-model page), and the active query that
    /// drives the in-transcript highlights is wiped whenever the sheet
    /// closes — only the cached string survives.
    @State private var lastSearchQuery: String = ""

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

    /// Pill is shown when the user has paused auto-scroll while the episode
    /// is loaded; hidden during search to avoid stacking UI.
    private var showJumpToPlaying: Bool {
        !autoScrollEnabled
            && activeSentenceID != nil
            && viewModel.transcriptSearchQuery.isEmpty
    }

    /// Formatted start time of the topmost visible sentence, surfaced by the
    /// floating scrub pill while scrolling.
    private var topVisibleTimestamp: String? {
        guard let id = topVisibleSentenceID else { return nil }
        return viewModel.transcriptSentences.first { $0.id == id }?.formattedStartTime
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.transcriptSource == "rss" && viewModel.hasTranscript {
                RSSTranscriptWarningBanner(
                    showRegenerateConfirmation: $showRegenerateConfirmation,
                    hasLocalAudio: viewModel.hasLocalAudio
                )
            }

            if viewModel.hasTranscript && !viewModel.isTranscriptProcessing {
                TranscriptStatusStrip(
                    viewModel: viewModel,
                    autoScrollEnabled: $autoScrollEnabled,
                    onShowTranslationPicker: onShowTranslationPicker,
                    onShowSubtitleSettings: onShowSubtitleSettings
                )
                Divider()
                transcriptScrollContent
            } else {
                transcriptStatusSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            TranscriptNavToolbar(
                viewModel: viewModel,
                showSearchSheet: $showSearchSheet,
                showCopySuccess: $showCopySuccess,
                onShowRegenerateConfirmation: onShowRegenerateConfirmation
            )
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
        .onChange(of: showSearchSheet) { _, isShowing in
            if isShowing {
                // Reopen: restore the previously typed query so the input
                // field is pre-filled and highlights re-appear.
                viewModel.transcriptSearchQuery = lastSearchQuery
            } else {
                // Dismiss: stash the query for the next reopen, then clear
                // the active query so transcript highlights disappear.
                lastSearchQuery = viewModel.transcriptSearchQuery
                viewModel.transcriptSearchQuery = ""
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            TranscriptSearchSheet(viewModel: viewModel) { _ in }
        }
        .alert("Copied", isPresented: $showCopySuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Transcript copied to clipboard")
        }
    }

    // MARK: - Scroll Content

    private var transcriptScrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
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
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .scrollPosition(id: $topVisibleSentenceID, anchor: .top)
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .interacting { autoScrollEnabled = false }
                let inMotion = newPhase == .interacting || newPhase == .decelerating
                if inMotion != showScrollTimestamp {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showScrollTimestamp = inMotion
                    }
                }
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
            .overlay(alignment: .topLeading) {
                if showScrollTimestamp, let stamp = topVisibleTimestamp {
                    Text(stamp)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: .capsule)
                        .padding(.leading, 12)
                        .padding(.top, 8)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                JumpToPlayingPill(isVisible: showJumpToPlaying) {
                    autoScrollEnabled = true
                    if let id = activeSentenceID {
                        withAnimation(.spring(duration: 0.5, bounce: 0.1)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Status Section

    @ViewBuilder
    private var transcriptStatusSection: some View {
        EpisodeTranscriptStatusView(viewModel: viewModel)
            .padding()
    }

}
