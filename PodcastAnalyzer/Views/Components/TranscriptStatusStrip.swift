//
//  TranscriptStatusStrip.swift
//  PodcastAnalyzer
//
//  Slim inline status strip beneath the navigation bar. The language chip
//  doubles as the single entry-point for translation + subtitle controls
//  (replaces the separate translate / settings toolbar buttons). The
//  Following chip toggles auto-scroll; the search counter appears while a
//  query is active.
//

import SwiftUI

struct TranscriptStatusStrip: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    @Binding var autoScrollEnabled: Bool

    var onShowTranslationPicker: () -> Void
    var onShowSubtitleSettings: () -> Void

    private var subtitleSettings: SubtitleSettingsManager { .shared }

    var body: some View {
        HStack(spacing: 8) {
            languageChip
            followingChip

            Spacer(minLength: 0)

            if !viewModel.transcript.transcriptSearchQuery.isEmpty {
                searchMatchChip
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.snappy(duration: 0.2), value: autoScrollEnabled)
        .animation(.snappy(duration: 0.2), value: viewModel.transcript.transcriptSearchQuery)
        .animation(.snappy(duration: 0.2), value: viewModel.translation.hasExistingTranslation)
    }

    // MARK: - Language Chip (Menu)

    /// Menu-backed chip: surfaces translation status visually and exposes
    /// translate / display-mode / subtitle-settings actions.
    private var languageChip: some View {
        Menu {
            languageMenuContent
        } label: {
            languageChipLabel
        }
        .menuOrder(.fixed)
        .disabled(viewModel.translation.translationStatus.isTranslating)
        .accessibilityLabel(Text(languageAccessibilityLabel))
        .accessibilityHint("Adjust translation and subtitle display")
    }

    @ViewBuilder
    private var languageMenuContent: some View {
        if viewModel.translation.hasExistingTranslation {
            Section("Display") {
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
                    .disabled(mode.requiresTranslation && !viewModel.translation.hasExistingTranslation)
                }
            }

            Section {
                Button {
                    onShowTranslationPicker()
                } label: {
                    Label("Change Translation…", systemImage: "translate")
                }
            }
        } else {
            Button {
                onShowTranslationPicker()
            } label: {
                Label("Translate…", systemImage: "translate")
            }
        }

        Section {
            Button {
                onShowSubtitleSettings()
            } label: {
                Label("Subtitle Settings…", systemImage: "gearshape")
            }
        }
    }

    @ViewBuilder
    private var languageChipLabel: some View {
        HStack(spacing: 6) {
            languageChipIcon
            Text(currentLanguageLabel)
                .font(.caption.weight(.medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(languageChipBackground, in: .capsule)
        .foregroundStyle(languageChipForeground)
    }

    @ViewBuilder
    private var languageChipIcon: some View {
        if viewModel.translation.translationStatus.isTranslating {
            TranslationProgressCircle(status: viewModel.translation.translationStatus)
                .frame(width: 14, height: 14)
        } else if case .failed = viewModel.translation.translationStatus {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
        } else if viewModel.translation.hasExistingTranslation {
            Image(systemName: "translate")
                .font(.caption)
        } else {
            Image(systemName: "globe")
                .font(.caption)
        }
    }

    private var languageChipBackground: AnyShapeStyle {
        if case .failed = viewModel.translation.translationStatus {
            return AnyShapeStyle(Color.red.opacity(0.15))
        }
        if viewModel.translation.hasExistingTranslation {
            return AnyShapeStyle(.tint.opacity(0.15))
        }
        return AnyShapeStyle(.thinMaterial)
    }

    private var languageChipForeground: AnyShapeStyle {
        if case .failed = viewModel.translation.translationStatus {
            return AnyShapeStyle(Color.red)
        }
        if viewModel.translation.hasExistingTranslation {
            return AnyShapeStyle(.tint)
        }
        return AnyShapeStyle(.secondary)
    }

    // MARK: - Following Chip

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
                autoScrollEnabled
                    ? AnyShapeStyle(.tint.opacity(0.15))
                    : AnyShapeStyle(.thinMaterial),
                in: .capsule
            )
            .foregroundStyle(autoScrollEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(autoScrollEnabled ? "Pause auto-scroll" : "Resume auto-scroll")
        .accessibilityHint("Keeps the transcript scrolled to the currently playing sentence")
    }

    // MARK: - Search Match Chip

    private var searchMatchChip: some View {
        let total = viewModel.transcript.searchMatchIds.count
        let position = total == 0 ? 0 : viewModel.transcript.currentMatchIndex + 1
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
        if let translated = viewModel.translation.selectedTranslationLanguage, viewModel.translation.hasExistingTranslation {
            return translated.shortName
        }
        let code = viewModel.podcastLanguage
        if code.isEmpty { return "Auto" }
        return code.uppercased()
    }

    private var languageAccessibilityLabel: String {
        if viewModel.translation.translationStatus.isTranslating { return "Translating in progress" }
        if case .failed = viewModel.translation.translationStatus { return "Translation failed" }
        if viewModel.translation.hasExistingTranslation,
           let lang = viewModel.translation.selectedTranslationLanguage {
            return "Translated to \(lang.displayName)"
        }
        return "Reading language: \(currentLanguageLabel)"
    }
}
