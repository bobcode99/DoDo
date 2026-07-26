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
import UniformTypeIdentifiers

struct EpisodeTranscriptView: View {
    @Bindable var viewModel: EpisodeDetailViewModel

    var onShowTranslationPicker: () -> Void
    var onShowSubtitleSettings: () -> Void
    var onShowRegenerateConfirmation: () -> Void

    @State private var autoScrollEnabled = true
    @State private var showRegenerateConfirmation = false
    @State private var showSearchSheet = false
    @State private var showCopySuccess = false
    @State private var showSRTImporter = false
    @State private var srtImportError: String?

    /// Search query cached for the lifetime of this view so reopening the
    /// search sheet recalls the last text. Cleared on view deinit (it's
    /// @State on a per-push view-model page), and the active query that
    /// drives the in-transcript highlights is wiped whenever the sheet
    /// closes — only the cached string survives.
    @State private var lastSearchQuery: String = ""

    /// Sentence the user picked from the search sheet. Drives a one-second
    /// flash highlight so the destination row is easy to spot after the
    /// sheet dismisses and the active search query is cleared.
    @State private var flashedSentenceID: Int?
    @State private var flashClearTask: Task<Void, Never>?

    /// Sentence to scroll to after the search sheet dismisses. Set by the
    /// sheet's onSelect closure (which doesn't have the `ScrollViewReader`
    /// proxy in scope) and consumed by an `.onChange` inside the reader.
    @State private var pendingSearchScrollTarget: Int?

    /// Reading audioManager.currentTime here registers @Observable observation,
    /// so the view re-evaluates as playback advances.
    ///
    /// During resume/seek/buffer transitions AVPlayer can briefly report
    /// `currentTime == 0` (or NaN) before settling on the saved position. If
    /// we surface that 0 directly, `activeID(at:)` returns nil and the karaoke
    /// highlight disappears for a frame or two — which the user perceives as
    /// "the highlight vanishes when I tap play after jumping to playing".
    /// Fall back to the saved playback position so the highlight stays put.
    private var currentTime: TimeInterval? {
        if viewModel.isCurrentEpisode {
            let live = viewModel.audioManager.currentTime
            if live.isFinite && live > 0 { return live }
            // Bridge only transient AVPlayer 0/NaN hiccups *while this episode
            // is the active one*. The sticky cache must stay scoped to this
            // branch: surfacing it when the episode is no longer current would
            // pin the highlight to the last-played time (a forward-ratcheted
            // value) instead of this episode's true position — the "playhead
            // at 9:00 but highlight at 9:52" bug.
            if let lastValidLiveTime { return lastValidLiveTime }
        }
        // Not the current episode: the authoritative position is the persisted
        // one for THIS episode, never the forward live cache.
        let saved = viewModel.lastPlaybackPosition
        return saved > 0 ? saved : nil
    }

    /// Last non-nil active sentence id. Used as a sticky fallback when
    /// `currentTime` momentarily can't resolve a match (e.g. AVPlayer reports
    /// 0/NaN during a seek), so the karaoke highlight doesn't blip out for a
    /// frame or two between updates.
    @State private var stickyActiveSentenceID: Int?

    /// Most recently observed *valid* `audioManager.currentTime`. Updated on
    /// every body render where the live time was finite and > 0. Used as the
    /// fallback inside `currentTime` so a transient AVPlayer hiccup doesn't
    /// rubber-band the highlight backwards to `viewModel.lastPlaybackPosition`
    /// (which is only persisted on pause/exit and can lag by minutes).
    @State private var lastValidLiveTime: TimeInterval?

    /// Deadline that gates `.onChange(of: activeSentenceID)`'s auto-scroll. Set
    /// whenever we kick off a programmatic scroll (Jump-to-Playing, search
    /// match navigation, search-pick destination). While this is in the
    /// future, sentence boundary advances do NOT re-fire `proxy.scrollTo` —
    /// otherwise the programmatic spring would be interrupted mid-flight by
    /// an `easeInOut` aimed at a newer sentence, the scroll would land
    /// somewhere between targets, and whichever row was genuinely active by
    /// the end of that fight would sit offscreen with no visible highlight.
    @State private var suppressAutoScrollUntil: Date = .distantPast

    /// Live lookup of the active sentence at `currentTime` — `nil` when the
    /// time is before the first sentence or unresolved.
    private var liveActiveSentenceID: Int? {
        guard let time = currentTime else { return nil }
        return viewModel.transcript.transcriptSentences.activeID(at: time)
    }

    /// Id of the sentence to highlight + auto-scroll to. Sticky — once we
    /// have a valid live id we cache it; if the live lookup briefly returns
    /// nil the highlight stays put instead of flashing off.
    private var activeSentenceID: Int? {
        liveActiveSentenceID ?? stickyActiveSentenceID
    }

    /// Pill is shown when the user has paused auto-scroll while the episode
    /// is loaded; hidden during search to avoid stacking UI.
    private var showJumpToPlaying: Bool {
        !autoScrollEnabled
            && activeSentenceID != nil
            && viewModel.transcript.transcriptSearchQuery.isEmpty
    }

    /// Audio file duration vs. the transcript's last timestamp. Non-nil only
    /// when they differ enough to actually drift the highlight — a transcript
    /// normally ends a little before the audio (outro/credits aren't
    /// transcribed), so we require both an absolute (90s) and relative (5%)
    /// gap before warning. The usual real cause is Dynamic Ad Insertion: the
    /// played mp3 was re-stitched with ads after the transcript was generated.
    private var durationMismatch: (audio: TimeInterval, transcript: TimeInterval)? {
        let audio = (viewModel.isCurrentEpisode && viewModel.audioManager.duration > 0)
            ? viewModel.audioManager.duration
            : viewModel.savedDuration
        guard audio > 0,
              let transcriptEnd = viewModel.transcript.transcriptSentences.last?.endTime,
              transcriptEnd > 0 else { return nil }
        let diff = abs(audio - transcriptEnd)
        guard diff > 90, diff > audio * 0.05 else { return nil }
        return (audio, transcriptEnd)
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.transcriptSource == "rss" && viewModel.hasTranscript {
                RSSTranscriptWarningBanner(
                    showRegenerateConfirmation: $showRegenerateConfirmation,
                    hasLocalAudio: viewModel.hasLocalAudio
                )
            } else if viewModel.hasTranscript, let mismatch = durationMismatch {
                TranscriptDurationMismatchBanner(
                    audioDuration: mismatch.audio,
                    transcriptDuration: mismatch.transcript
                )
            }

            if viewModel.hasTranscript && !viewModel.transcript.isTranscriptProcessing {
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
        .overlay {
            if viewModel.isDiarizing {
                DiarizationProgressOverlay()
            }
        }
        .toolbar {
            TranscriptNavToolbar(
                viewModel: viewModel,
                showSearchSheet: $showSearchSheet,
                showCopySuccess: $showCopySuccess,
                showSRTImporter: $showSRTImporter,
                onShowRegenerateConfirmation: onShowRegenerateConfirmation
            )
        }
        // SRT files often carry no specific UTType (public.data), so accept
        // broadly and validate by parsing instead of by content type.
        .fileImporter(isPresented: $showSRTImporter, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                importSRT(from: url)
            case .failure(let error):
                srtImportError = error.localizedDescription
            }
        }
        .alert(
            "Import Failed",
            isPresented: Binding(
                get: { srtImportError != nil },
                set: { if !$0 { srtImportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(srtImportError ?? "")
        }
        .onChange(of: showRegenerateConfirmation) { _, isShowing in
            if isShowing {
                onShowRegenerateConfirmation()
                showRegenerateConfirmation = false
            }
        }
        .onChange(of: viewModel.transcript.transcriptSearchQuery) { _, newQuery in
            viewModel.transcript.updateSearchMatches(query: newQuery)
        }
        .onChange(of: viewModel.transcript.transcriptSentences.count) { _, _ in
            // If the underlying sentence list changes (regroup after
            // translation toggle, transcript regenerated, etc.) the sticky
            // cache may point at an id that no longer exists. Drop it so the
            // next live lookup re-seeds it cleanly.
            stickyActiveSentenceID = nil
        }
        .onChange(of: viewModel.isCurrentEpisode) { _, isCurrent in
            // When another episode takes over, drop the forward-ratcheted
            // caches so the highlight falls back to this episode's persisted
            // position instead of the last live value we observed while it
            // was playing.
            if !isCurrent {
                lastValidLiveTime = nil
                stickyActiveSentenceID = nil
            }
        }
        .onChange(of: showSearchSheet) { _, isShowing in
            if isShowing {
                // Reopen: restore the previously typed query so the input
                // field is pre-filled and highlights re-appear.
                viewModel.transcript.transcriptSearchQuery = lastSearchQuery
            } else {
                // Dismiss: stash the query for the next reopen, then clear
                // the active query so transcript highlights disappear.
                lastSearchQuery = viewModel.transcript.transcriptSearchQuery
                viewModel.transcript.transcriptSearchQuery = ""
            }
        }
        .sheet(isPresented: $showSearchSheet) {
            TranscriptSearchSheet(viewModel: viewModel) { sentenceID in
                // Pause auto-scroll — the user explicitly chose where to land,
                // so we shouldn't keep snapping back to the playhead.
                autoScrollEnabled = false
                pendingSearchScrollTarget = sentenceID
                flashedSentenceID = sentenceID
                flashClearTask?.cancel()
                flashClearTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        flashedSentenceID = nil
                    }
                }
            }
        }
        .alert("Copied", isPresented: $showCopySuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Transcript copied to clipboard")
        }
        .alert(
            "Speakers",
            isPresented: Binding(
                get: { viewModel.diarizationMessage != nil },
                set: { if !$0 { viewModel.diarizationMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.diarizationMessage ?? "")
        }
    }

    // MARK: - Scroll Content

    private var transcriptScrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                SentenceBasedTranscriptView(
                    sentences: viewModel.transcript.transcriptSentences,
                    currentTime: currentTime,
                    searchQuery: viewModel.transcript.transcriptSearchQuery,
                    onSegmentTap: viewModel.transcript.seekToSegment,
                    subtitleMode: viewModel.translation.effectiveDisplayMode,
                    flashedSentenceID: flashedSentenceID
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            // NOTE: do NOT add `.scrollPosition(id:anchor:.top)` here. Pairing
            // that binding (which keeps a chosen sentence anchored to .top)
            // with `proxy.scrollTo(id, anchor: .center)` makes the two modifiers
            // fight in opposite directions — the system writes the new top
            // sentence id into the binding as the scroll moves toward center,
            // and `.scrollPosition` immediately re-scrolls that sentence to
            // top, which inverts the direction. The user saw this as the
            // transcript bouncing between the very top of the credits and
            // the playing sentence, continuously.
            .onScrollPhaseChange { _, newPhase in
                if newPhase == .interacting { autoScrollEnabled = false }
            }
            .onChange(of: liveActiveSentenceID, initial: true) { _, newID in
                // Promote any non-nil live lookup into the sticky cache so
                // the highlight survives transient AVPlayer time hiccups.
                if let newID { stickyActiveSentenceID = newID }
                // Cheap cache update: only fires on sentence boundary
                // (every few seconds), not per audio tick. Within a sentence
                // the value is stale, but the fallback only matters during
                // an AVPlayer hiccup — being stale by < 1 sentence is far
                // better than rubber-banding to `lastPlaybackPosition`.
                let live = viewModel.audioManager.currentTime
                if live.isFinite && live > 0 { lastValidLiveTime = live }
            }
            .onChange(of: activeSentenceID) { _, newID in
                guard autoScrollEnabled,
                      let id = newID,
                      viewModel.transcript.transcriptSearchQuery.isEmpty,
                      Date() >= suppressAutoScrollUntil else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onChange(of: viewModel.transcript.currentMatchIndex) { _, _ in
                guard !viewModel.transcript.searchMatchIds.isEmpty else { return }
                let matchId = viewModel.transcript.searchMatchIds[viewModel.transcript.currentMatchIndex]
                suppressAutoScrollUntil = Date().addingTimeInterval(0.4)
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(matchId, anchor: .center)
                }
            }
            .onChange(of: pendingSearchScrollTarget) { _, target in
                guard let target else { return }
                pendingSearchScrollTarget = nil
                suppressAutoScrollUntil = Date().addingTimeInterval(0.45)
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(target, anchor: .center)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                JumpToPlayingPill(isVisible: showJumpToPlaying) {
                    autoScrollEnabled = true
                    suppressAutoScrollUntil = Date().addingTimeInterval(0.45)
                    if let id = activeSentenceID {
                        withAnimation(.easeInOut(duration: 0.4)) {
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

    // MARK: - SRT Import

    /// Imports a user-picked .srt file as this episode's transcript.
    /// Validates by parsing — an unparseable file must not overwrite an
    /// existing transcript with an empty one.
    private func importSRT(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let content = try? String(contentsOf: url, encoding: .utf8),
              !SRTParser.parseSegments(from: content).isEmpty else {
            srtImportError = "Couldn't read subtitles from “\(url.lastPathComponent)”. Make sure it's a valid SRT file."
            return
        }
        do {
            try TranscriptStore.shared.saveTranscript(
                srtContent: content,
                episodeTitle: viewModel.episode.title,
                podcastTitle: viewModel.podcastTitle,
                source: "imported"
            )
            viewModel.transcript.checkTranscriptStatus()
        } catch {
            srtImportError = error.localizedDescription
        }
    }
}

// MARK: - Diarization Progress

/// Blocking, indeterminate progress cover shown while speaker identification
/// runs. The work is off-main, so this spinner actually animates and the rest
/// of the app stays responsive underneath the scrim.
private struct DiarizationProgressOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("Identifying speakers…")
                    .font(.headline)
                // Honest expectation-setting: first run also pulls the model.
                Text("Runs on-device. The first time also downloads a ~100 MB model, so this can take a minute.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .transition(.opacity)
    }
}
