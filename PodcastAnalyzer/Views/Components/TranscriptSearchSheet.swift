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
                } else if viewModel.transcript.searchMatchIds.isEmpty {
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
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("Close search")
                }
            }
        }
        .onAppear {
            localQuery = viewModel.transcript.transcriptSearchQuery
            fieldFocused = true
        }
        .onChange(of: localQuery) { _, newValue in
            viewModel.transcript.transcriptSearchQuery = newValue
            viewModel.transcript.updateSearchMatches(query: newValue)
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
                    Button {
                        localQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: .rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.secondary.opacity(0.15), lineWidth: 1)
            )

            Button {
                fieldFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(10)
                    .background(.thickMaterial, in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
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
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No matches")
                .font(.headline)
            Text("Try a different word or shorter phrase.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsHeader: some View {
        Text("Showing \(viewModel.transcript.searchMatchIds.count) result\(viewModel.transcript.searchMatchIds.count == 1 ? "" : "s")")
            .font(.subheadline)
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.tint.opacity(0.08))
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let lookup = sentenceLookup
                ForEach(Array(viewModel.transcript.searchMatchIds.enumerated()), id: \.element) { index, sentenceID in
                    if let sentence = lookup[sentenceID] {
                        TranscriptSearchResultRow(
                            sentence: sentence,
                            query: localQuery
                        )
                        .contentShape(.rect)
                        .onTapGesture {
                            handleSelect(matchIndex: index, sentenceID: sentenceID)
                        }
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var sentenceLookup: [TranscriptSentence.ID: TranscriptSentence] {
        Dictionary(uniqueKeysWithValues: viewModel.transcript.groupedSentences.map { ($0.id, $0) })
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
