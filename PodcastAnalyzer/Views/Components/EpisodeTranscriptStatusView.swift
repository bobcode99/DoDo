
import SwiftUI

struct EpisodeTranscriptStatusView: View {
    @Bindable var viewModel: EpisodeDetailViewModel

    private var effectiveEngine: TranscriptEngine {
        viewModel.selectedTranscriptEngine ?? TranscriptEngine(
            rawValue: UserDefaults.standard.string(forKey: "transcriptEngine") ?? ""
        ) ?? .appleSpeech
    }

    private func resolvedLanguage(_ code: String) -> String {
        guard !code.isEmpty else { return code }
        let locales = SettingsViewModel.locales(for: effectiveEngine)
        let lower = code.lowercased()
        if locales.contains(where: { $0.id == lower }) { return lower }
        if let match = locales.first(where: { $0.id.hasPrefix(lower + "-") }) { return match.id }
        let base = lower.split(separator: "-").first.map(String.init) ?? lower
        if let match = locales.first(where: { $0.id == base || $0.id.hasPrefix(base + "-") }) { return match.id }
        return lower
    }

    private var pickerLocales: [SettingsViewModel.TranscriptLocaleOption] {
        let standard = SettingsViewModel.locales(for: effectiveEngine)
        // If the podcast language is unknown, return the standard list as-is.
        // An empty/missing language must never inject a phantom "(podcast)" entry.
        guard !viewModel.podcastLanguage.isEmpty else { return standard }
        let podcastLang = viewModel.podcastLanguage.lowercased()
        let resolved = resolvedLanguage(podcastLang)
        if standard.contains(where: { $0.id == resolved }) { return standard }
        let displayName = Locale.current.localizedString(forLanguageCode: podcastLang) ?? podcastLang
        return [SettingsViewModel.TranscriptLocaleOption(id: podcastLang, name: "\(displayName) (podcast)")] + standard
    }

    private var transcriptLanguageName: String {
        if effectiveEngine == .whisper, viewModel.selectedTranscriptLanguage == nil {
            if let detected = viewModel.transcriptDetectedLanguage {
                let name = pickerLocales.first { $0.id == detected }?.name
                    ?? Locale.current.localizedString(forLanguageCode: detected)
                    ?? detected
                return name
            }
            return "Auto-detect"
        }
        let code = viewModel.selectedTranscriptLanguage ?? viewModel.podcastLanguage
        return pickerLocales.first { $0.id == resolvedLanguage(code) }?.name ?? code
    }

    /// Whether the current engine + audio state can generate without downloading first.
    private var canGenerate: Bool {
        viewModel.hasLocalAudio || effectiveEngine == .yapServer
    }

    var body: some View {
        switch viewModel.transcriptState {
        case .idle:
            idleView
        case .downloadingModel(let progress):
            progressView(label: "Downloading Speech Model...", progress: progress)
        case .transcribing(let progress):
            progressView(label: "Generating Transcript (\(transcriptLanguageName))...", progress: progress)
        case .completed:
            completedView
        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - Idle

    @ViewBuilder
    private var idleView: some View {
        if viewModel.hasRSSTranscriptAvailable {
            rssAvailableView
        } else if viewModel.isDownloadingRSSTranscript {
            rssDownloadingView
        } else {
            generateConfigView
        }
    }

    private var rssAvailableView: some View {
        ContentUnavailableView {
            Label("Transcript Available", systemImage: "captions.bubble")
        } description: {
            Text("This episode has a transcript from the podcast feed.")
        } actions: {
            Button {
                viewModel.downloadRSSTranscript()
            } label: {
                Label("Download Transcript", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var rssDownloadingView: some View {
        ContentUnavailableView {
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Downloading Transcript")
                    .font(.headline)
            }
        } description: {
            Text("Fetching the transcript from the podcast feed.")
        }
    }

    /// Unified config view: always shows engine + language pickers.
    /// The action button adapts to what's available.
    private var generateConfigView: some View {
        VStack(spacing: 16) {
            // Icon + status
            VStack(spacing: 8) {
                Image(systemName: canGenerate ? "waveform" : "arrow.down.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(canGenerate ? .blue : .secondary)
                Text(canGenerate ? "Ready to Generate" : "Download Required")
                    .font(.headline)
                Text(statusDescription)
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            Divider()

            // Engine picker
            enginePicker

            languagePicker

            engineHint

            Divider()

            // Primary action
            if canGenerate {
                Button(action: { viewModel.generateTranscript() }) {
                    Label("Generate Transcript", systemImage: "text.bubble")
                        .font(.subheadline)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: { viewModel.startDownload() }) {
                    Label("Download Episode", systemImage: "arrow.down.circle")
                        .font(.subheadline)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var statusDescription: String {
        if canGenerate {
            if !viewModel.isModelReady && effectiveEngine == .whisper {
                return "Speech recognition model will be downloaded on first use."
            }
            if effectiveEngine == .yapServer && !viewModel.hasLocalAudio {
                return "The episode will be streamed directly to your Yap server."
            }
            return "Select an engine and language, then tap Generate."
        }
        return "Download the episode audio to generate a transcript locally, or switch to Yap Server to stream instead."
    }

    private var enginePicker: some View {
        Picker("Engine", selection: Binding(
            get: { effectiveEngine },
            set: { newEngine in
                viewModel.selectedTranscriptEngine = newEngine
                guard newEngine != .whisper, let selected = viewModel.selectedTranscriptLanguage else { return }
                let resolved = resolvedLanguage(selected)
                if !SettingsViewModel.locales(for: newEngine).contains(where: { $0.id == resolved }) {
                    viewModel.selectedTranscriptLanguage = nil
                }
            }
        )) {
            ForEach(TranscriptEngine.allCases) { engine in
                Label(engine.displayName, systemImage: engine.systemImage).tag(engine)
            }
        }
        .pickerStyle(.menu)
        .font(.subheadline)
    }

    private var languagePicker: some View {
        Picker("Language", selection: Binding(
            get: {
                if effectiveEngine == .whisper {
                    return viewModel.selectedTranscriptLanguage ?? "auto"
                }
                if let selected = viewModel.selectedTranscriptLanguage {
                    return resolvedLanguage(selected)
                }
                let lang = viewModel.podcastLanguage
                guard !lang.isEmpty else {
                    // Language unknown — fall back to device locale so the picker
                    // doesn't land on a random first entry or a phantom row.
                    let deviceCode = Locale.current.language.languageCode?.identifier ?? "en"
                    return resolvedLanguage(deviceCode)
                }
                return resolvedLanguage(lang)
            },
            set: { newValue in
                if effectiveEngine == .whisper {
                    viewModel.selectedTranscriptLanguage = newValue == "auto" ? nil : newValue
                } else {
                    // Always store the explicit selection — never nil-optimize.
                    // Nil-optimizing caused the picker to show "zh-tw" (first locale,
                    // accidental match for empty podcastLanguage) while selectedTranscriptLanguage
                    // remained nil, so generateTranscript() fell back to getPodcastLanguage() → "en".
                    viewModel.selectedTranscriptLanguage = newValue
                }
            }
        )) {
            if effectiveEngine == .whisper {
                Text("Auto-detect").tag("auto")
            }
            ForEach(pickerLocales) { locale in
                Text(locale.name).tag(locale.id)
            }
        }
        .pickerStyle(.menu)
        .font(.subheadline)
    }

    @ViewBuilder
    private var engineHint: some View {
        if effectiveEngine == .whisper {
            Text("Auto-detect identifies the language automatically.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        } else if effectiveEngine == .appleSpeech {
            Text("Apple Speech requires a model download per language.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    // MARK: - Progress

    private func progressView(label: String, progress: Double) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
                .symbolEffect(.variableColor.iterative, options: .repeat(.continuous))

            VStack(spacing: 8) {
                Text(label)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 260)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button("Cancel", role: .cancel) { viewModel.cancelTranscript() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(label), \(Int(progress * 100)) percent"))
    }

    // MARK: - Completed

    private var completedView: some View {
        ContentUnavailableView {
            Label("Transcript Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } description: {
            Text("Tap a sentence to seek playback.")
        }
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Transcription Failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } description: {
            Text(message)
        } actions: {
            Button {
                viewModel.generateTranscript()
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }
}
