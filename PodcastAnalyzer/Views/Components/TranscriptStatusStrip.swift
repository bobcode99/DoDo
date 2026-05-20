//
//  TranscriptStatusStrip.swift
//  PodcastAnalyzer
//
//  Slim inline status strip beneath the navigation bar. Shows the current
//  reading language, whether playback-following is on, and a live search
//  match counter. Tap-targets are pill-shaped chips, sized for HIG.
//

import SwiftUI

struct TranscriptStatusStrip: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    @Binding var autoScrollEnabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            languageChip
            followingChip

            Spacer(minLength: 0)

            if !viewModel.transcriptSearchQuery.isEmpty {
                searchMatchChip
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.snappy(duration: 0.2), value: autoScrollEnabled)
        .animation(.snappy(duration: 0.2), value: viewModel.transcriptSearchQuery)
    }

    // MARK: - Chips

    private var languageChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe")
                .font(.caption)
            Text(currentLanguageLabel)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: .capsule)
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text("Reading language: \(currentLanguageLabel)"))
    }

    private var followingChip: some View {
        Button {
            autoScrollEnabled.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: autoScrollEnabled ? "play.fill" : "pause.fill")
                    .font(.caption2)
                Text(autoScrollEnabled ? "Following" : "Paused")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                autoScrollEnabled ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(.thinMaterial),
                in: .capsule
            )
            .foregroundStyle(autoScrollEnabled ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(autoScrollEnabled ? "Pause auto-scroll" : "Resume auto-scroll")
        .accessibilityHint("Keeps the transcript scrolled to the currently playing sentence")
    }

    private var searchMatchChip: some View {
        let total = viewModel.searchMatchIds.count
        let position = total == 0 ? 0 : viewModel.currentMatchIndex + 1
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption2)
            Text("\(position) / \(total)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.blue.opacity(0.15), in: .capsule)
        .foregroundStyle(.blue)
        .accessibilityLabel(Text("Search match \(position) of \(total)"))
    }

    // MARK: - Labels

    /// Reading language: target when translated, else source / podcast language.
    private var currentLanguageLabel: String {
        if let translated = viewModel.selectedTranslationLanguage, viewModel.hasExistingTranslation {
            return translated.shortName
        }
        let code = viewModel.podcastLanguage
        if code.isEmpty { return "Auto" }
        return code.uppercased()
    }
}
