//
//  TranscriptSearchSheet.swift
//  PodcastAnalyzer
//
//  Dedicated full-screen transcript search. Replaces the inline-toolbar search
//  field. Tap a result row → dismiss + scroll the transcript to that sentence
//  (the parent's onChange(of: viewModel.transcript.currentMatchIndex) drives the scroll).
//  Does NOT touch audio playback — selection is navigate-only by design.
//

import SwiftUI

struct TranscriptSearchSheet: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    var onSelect: (TranscriptSentence.ID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var localQuery: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Divider()

                if localQuery.isEmpty {
                    emptyState
                } else if viewModel.transcript.searchMatches.isEmpty {
                    noResults
                } else {
                    resultsHeader
                    resultsList
                }
            }
            .navigationTitle("Search Transcript")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Close search", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            localQuery = viewModel.transcript.transcriptSearchQuery
            fieldFocused = true
        }
        .onChange(of: localQuery) { _, newValue in
            viewModel.transcript.transcriptSearchQuery = newValue
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Search transcript...", text: $localQuery)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .submitLabel(.search)

                if !localQuery.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill") {
                        localQuery = ""
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    // 44pt target; the negative inset keeps the glyph where it was.
                    .frame(width: 44, height: 44)
                    .padding(.trailing, -12)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.regularMaterial, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.secondary.opacity(0.15), lineWidth: 1)
            }

            Button("Search", systemImage: "magnifyingglass") {
                fieldFocused = true
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.headline)
            .frame(width: 44, height: 44)
            .background(.thickMaterial, in: .rect(cornerRadius: 10))
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Search the transcript")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Type a word or phrase to find every sentence that mentions it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No matches")
                .font(.headline)
            Text("Try a different word or shorter phrase.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsHeader: some View {
        // Inflected, not a hand-rolled "s": the suffix was passed to every language
        // as an argument, so zh-Hant read "顯示 64 個結果s".
        Text("Showing ^[\(viewModel.transcript.searchMatches.count) result](inflect: true)")
            .font(.subheadline)
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.tint.opacity(0.08))
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.transcript.searchMatches.enumerated(), id: \.element.id) { index, sentence in
                    VStack(spacing: 0) {
                        Button {
                            handleSelect(matchIndex: index, sentenceID: sentence.id)
                        } label: {
                            TranscriptSearchResultRow(
                                sentence: sentence,
                                query: localQuery
                            )
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func handleSelect(matchIndex: Int, sentenceID: TranscriptSentence.ID) {
        // Navigate-only: setting currentMatchIndex drives the transcript scroll
        // via the parent's onChange handler. We intentionally do NOT call
        // seekToSegment here — that would start audio playback, which users
        // don't want when they're just searching for a passage.
        viewModel.transcript.currentMatchIndex = matchIndex
        onSelect(sentenceID)
        dismiss()
    }
}

// MARK: - Result Row

private struct TranscriptSearchResultRow: View {
    let sentence: TranscriptSentence
    let query: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(sentence.formattedStartTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                SearchHighlightedText(text: sentence.text, query: query)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
