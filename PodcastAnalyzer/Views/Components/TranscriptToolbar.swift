//
//  TranscriptToolbar.swift
//  PodcastAnalyzer
//
//  Always-visible transcript toolbar: search, translate, auto-scroll, display mode, options menu.
//  Extracted from EpisodeDetailView.transcriptHeader.
//

import SwiftUI

struct TranscriptToolbar: View {
    @Bindable var viewModel: EpisodeDetailViewModel
    @Binding var autoScrollEnabled: Bool

    var onShowSearch: () -> Void
    var onShowTranslationPicker: () -> Void
    var onShowSubtitleSettings: () -> Void
    var onShowRegenerateOptions: () -> Void

    private var subtitleSettings: SubtitleSettingsManager { .shared }

    @State private var showCopySuccess = false

    var body: some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)

            // Search button — opens dedicated search sheet
            Button {
                onShowSearch()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundStyle(viewModel.transcriptSearchQuery.isEmpty ? Color.secondary : Color.blue)
                    if !viewModel.transcriptSearchQuery.isEmpty {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                    }
                }
            }
            .accessibilityLabel("Search transcript")

            // Translate button with circular progress — shows language picker
            Button {
                onShowTranslationPicker()
            } label: {
                    if viewModel.translationStatus.isTranslating {
                        TranslationProgressCircle(status: viewModel.translationStatus)
                            .frame(width: 28, height: 28)
                    } else if case .failed = viewModel.translationStatus {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.red)
                    } else if viewModel.hasExistingTranslation {
                        ZStack(alignment: .bottomTrailing) {
                            Image(systemName: "translate.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.blue)
                            if let lang = viewModel.selectedTranslationLanguage {
                                Text(lang.shortName)
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(.blue)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                                    .offset(x: 4, y: 4)
                            }
                        }
                    } else {
                        Image(systemName: "translate")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(viewModel.translationStatus.isTranslating)

                // Auto-scroll toggle
                Button {
                    autoScrollEnabled.toggle()
                } label: {
                    Image(systemName: "arrow.up.and.down.text.horizontal")
                        .font(.system(size: 18))
                        .foregroundStyle(autoScrollEnabled ? .blue : .secondary)
                }
                .accessibilityLabel(autoScrollEnabled ? "Disable auto-scroll" : "Enable auto-scroll")

                // Display mode picker (when translation exists) or settings button
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
                            .font(.system(size: 20))
                            .foregroundStyle(.blue)
                    }
                } else {
                    Button {
                        onShowSubtitleSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Subtitle settings")
                }

                // Options menu
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

                    Divider()

                    Section("Copy") {
                        Button(action: {
                            viewModel.copyTranscriptToClipboard()
                            showCopySuccess = true
                        }) {
                            Label("Copy All (with timestamps)", systemImage: "doc.on.doc")
                        }

                        Button(action: {
                            PlatformClipboard.string = viewModel.cleanTranscriptText
                            showCopySuccess = true
                        }) {
                            Label("Copy Text Only", systemImage: "text.alignleft")
                        }
                    }

                    Button(
                        role: .destructive,
                        action: {
                            onShowRegenerateOptions()
                        }
                    ) {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Transcript options")
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.transcriptSearchQuery.isEmpty)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .alert("Copied", isPresented: $showCopySuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Transcript copied to clipboard")
        }
    }
}
