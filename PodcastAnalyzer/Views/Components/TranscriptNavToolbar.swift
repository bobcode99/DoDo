//
//  TranscriptNavToolbar.swift
//  PodcastAnalyzer
//
//  Trailing navigation-bar toolbar items for EpisodeTranscriptView: just
//  Search and a transcript-actions menu (info + share/import + copy +
//  regenerate). With nothing transcribed yet, only the info line and Import
//  remain — everything else acts on segments that do not exist.
//  Translation and subtitle settings live on the language chip in the
//  status strip instead of the nav bar.
//

import SwiftUI

struct TranscriptNavToolbar: ToolbarContent {
    @Bindable var viewModel: EpisodeDetailViewModel
    @Binding var showSearchSheet: Bool
    @Binding var showCopySuccess: Bool
    @Binding var showSRTImporter: Bool

    var onShowRegenerateConfirmation: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            searchButton
        }

        ToolbarItem(placement: .primaryAction) {
            transcriptActionsMenu
        }
    }

    // MARK: - Items

    private var searchButton: some View {
        Button {
            showSearchSheet = true
        } label: {
            Image(systemName: viewModel.transcript.transcriptSearchQuery.isEmpty
                  ? "magnifyingglass"
                  : "magnifyingglass.circle.fill")
        }
        .accessibilityLabel("Search transcript")
    }

    /// Nothing has been transcribed yet. Every action below except importing
    /// operates on segments that do not exist: sharing writes an empty .srt,
    /// copying puts nothing on the clipboard, and "Regenerate" offers to redo
    /// work never done — first-time generation lives on its own screen
    /// (TranscriptGenerateConfigView), so hiding it here strands nobody.
    private var isEmpty: Bool { viewModel.transcript.transcriptSegments.isEmpty }

    private var transcriptActionsMenu: some View {
        Menu {
            Section {
                // A stale date beside no segments describes a transcript that
                // is not there.
                if let date = viewModel.transcript.cachedTranscriptDate, !isEmpty {
                    Label(
                        "Generated \(Formatters.formatDate(date, time: .shortened))",
                        systemImage: "clock"
                    )
                }
                Label(
                    "\(viewModel.transcript.transcriptSegments.count) segments",
                    systemImage: "text.alignleft"
                )
            }

            Section("Share") {
                if !isEmpty {
                    Button {
                        if let url = TranscriptStore.shared.exportSRTFile(
                            episodeTitle: viewModel.episode.title,
                            podcastTitle: viewModel.podcastTitle
                        ) {
                            PlatformShareSheet.share(url: url)
                        }
                    } label: {
                        Label("Share as Subtitles (.srt)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        if let url = TranscriptStore.shared.exportShareFile(
                            episodeTitle: viewModel.episode.title,
                            podcastTitle: viewModel.podcastTitle
                        ) {
                            PlatformShareSheet.share(url: url)
                        }
                    } label: {
                        Label("Share for DoDo", systemImage: "square.and.arrow.up.on.square")
                    }
                }

                // Survives the empty case: it is the one action that still
                // means something with nothing stored, and the only way to put
                // a transcript here without running a transcription.
                Button {
                    showSRTImporter = true
                } label: {
                    Label("Import Subtitles (.srt)", systemImage: "square.and.arrow.down")
                }
            }

            if !isEmpty {
                Section("Copy") {
                    Button {
                        viewModel.transcript.copyTranscriptToClipboard()
                        showCopySuccess = true
                    } label: {
                        Label("Copy All (with timestamps)", systemImage: "doc.on.doc")
                    }
                    Button {
                        PlatformClipboard.string = viewModel.transcript.cleanTranscriptText
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
            }
        } label: {
            Image(systemName: "doc.text")
        }
        .accessibilityLabel("Transcript actions")
    }
}

// MARK: - Preview

#if DEBUG
private struct TranscriptNavToolbarPreviewHost: View {
    @State private var viewModel = EpisodeDetailViewModel(
        episode: PodcastEpisodeInfo(
            title: "Episode 42: The Future of Podcasting",
            podcastEpisodeDescription: "A deep dive into modern podcast tooling.",
            pubDate: .now,
            audioURL: "https://example.com/audio.mp3",
            imageURL: nil,
            duration: 3600,
            guid: "preview-guid"
        ),
        podcastTitle: "The Sample Podcast",
        fallbackImageURL: nil,
        podcastLanguage: "en"
    )
    @State private var showSearchSheet = false
    @State private var showCopySuccess = false
    @State private var showSRTImporter = false

    var body: some View {
        NavigationStack {
            Text("Transcript content goes here")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Transcript")
                .toolbar {
                    TranscriptNavToolbar(
                        viewModel: viewModel,
                        showSearchSheet: $showSearchSheet,
                        showCopySuccess: $showCopySuccess,
                        showSRTImporter: $showSRTImporter,
                        onShowRegenerateConfirmation: {}
                    )
                }
        }
    }
}

#Preview("Default") {
    TranscriptNavToolbarPreviewHost()
}
#endif
