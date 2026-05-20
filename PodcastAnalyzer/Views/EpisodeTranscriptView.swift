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

    private var subtitleSettings: SubtitleSettingsManager { .shared }

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
                    autoScrollEnabled: $autoScrollEnabled
                )
                Divider()
                transcriptScrollContent
            } else {
                transcriptStatusSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar { transcriptToolbarContent }
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
                LazyVStack(alignment: .leading, spacing: 6) {
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
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .interacting { autoScrollEnabled = false }
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var transcriptToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showSearchSheet = true
            } label: {
                Image(systemName: viewModel.transcriptSearchQuery.isEmpty
                      ? "magnifyingglass"
                      : "magnifyingglass.circle.fill")
            }
            .accessibilityLabel("Search transcript")
        }

        ToolbarItem(placement: .primaryAction) {
            if viewModel.hasExistingTranslation {
                Menu {
                    ForEach(SubtitleDisplayMode.allCases, id: \.self) { mode in
                        Button {
                            subtitleSettings.displayMode = mode
                        } label: {
                            if subtitleSettings.displayMode == mode {
                                Label(mode.displayName, systemImage: "checkmark")
                            } else {
                                Label(mode.displayName, systemImage: mode.icon)
                            }
                        }
                        .disabled(mode.requiresTranslation && !viewModel.hasExistingTranslation)
                    }
                    Divider()
                    Button {
                        onShowSubtitleSettings()
                    } label: {
                        Label("More Settings...", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "textformat.alt")
                }
                .accessibilityLabel("Display mode")
            } else {
                Button {
                    onShowSubtitleSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Subtitle settings")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Section {
                    if let date = viewModel.cachedTranscriptDate {
                        Label(
                            "Generated \(date.formatted(date: .abbreviated, time: .shortened))",
                            systemImage: "clock"
                        )
                    }
                    Label(
                        "\(viewModel.transcriptSegments.count) segments",
                        systemImage: "text.alignleft"
                    )
                }

                Section("Copy") {
                    Button {
                        viewModel.copyTranscriptToClipboard()
                        showCopySuccess = true
                    } label: {
                        Label("Copy All (with timestamps)", systemImage: "doc.on.doc")
                    }
                    Button {
                        PlatformClipboard.string = viewModel.cleanTranscriptText
                        showCopySuccess = true
                    } label: {
                        Label("Copy Text Only", systemImage: "text.alignleft")
                    }
                }

                Button(role: .destructive) {
                    onShowRegenerateConfirmation()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "doc.text")
            }
            .accessibilityLabel("Transcript actions")
        }
    }
}
