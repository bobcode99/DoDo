
import SwiftUI

struct EpisodeTranscriptStatusView: View {
    @Bindable var viewModel: EpisodeDetailViewModel

    /// The effective engine: per-episode override or global Settings default.
    private var effectiveEngine: TranscriptEngine {
        viewModel.selectedTranscriptEngine ?? TranscriptEngine(
            rawValue: UserDefaults.standard.string(forKey: "transcriptEngine") ?? ""
        ) ?? .appleSpeech
    }

    /// Maps a bare language code (e.g. "en") to the first matching locale ID (e.g. "en-us")
    /// so the Picker always has a valid tagged selection.
    private func resolvedLanguage(_ code: String) -> String {
        let locales = SettingsViewModel.locales(for: effectiveEngine)
        let lower = code.lowercased()
        // Exact match first
        if locales.contains(where: { $0.id == lower }) { return lower }
        // Prefix match: "en" → "en-us" (first match)
        if let match = locales.first(where: { $0.id.hasPrefix(lower + "-") }) {
            return match.id
        }
        // Reverse prefix: "en-us" base "en" matches "en-us" in list
        let base = lower.split(separator: "-").first.map(String.init) ?? lower
        if let match = locales.first(where: { $0.id == base || $0.id.hasPrefix(base + "-") }) {
            return match.id
        }
        return lower
    }

    /// Builds the picker options based on the effective engine,
    /// dynamically adding the podcast language if not in the list.
    private var pickerLocales: [SettingsViewModel.TranscriptLocaleOption] {
        let standard = SettingsViewModel.locales(for: effectiveEngine)
        let podcastLang = viewModel.podcastLanguage.lowercased()
        let resolved = resolvedLanguage(podcastLang)
        if standard.contains(where: { $0.id == resolved }) {
            return standard
        }
        let displayName = Locale.current.localizedString(forLanguageCode: podcastLang) ?? podcastLang
        let dynamic = SettingsViewModel.TranscriptLocaleOption(id: podcastLang, name: "\(displayName) (podcast)")
        return [dynamic] + standard
    }

    private var transcriptLanguageName: String {
        if effectiveEngine == .whisper, viewModel.selectedTranscriptLanguage == nil {
            return "Auto-detect"
        }
        let code = viewModel.selectedTranscriptLanguage ?? viewModel.podcastLanguage
        let resolved = resolvedLanguage(code)
        return pickerLocales.first { $0.id == resolved }?.name ?? code
    }

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.transcriptState {
            case .idle:
                // Check RSS transcript availability first
                if viewModel.hasRSSTranscriptAvailable {
                    VStack(spacing: 12) {
                        Image(systemName: "captions.bubble")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)
                        Text("Transcript Available").font(.headline)
                        Text("This episode has a transcript from the podcast feed.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(action: { viewModel.downloadRSSTranscript() }) {
                            Label("Download Transcript", systemImage: "arrow.down.circle")
                                .font(.subheadline)
                                .padding(.horizontal, 20).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if viewModel.isDownloadingRSSTranscript {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Downloading Transcript").font(.headline)
                            .padding(.top, 8)
                    }
                } else if viewModel.hasLocalAudio {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)
                        Text("Ready to Generate Transcript").font(.headline)
                        if !viewModel.isModelReady {
                            Text(
                                "Speech recognition model will be downloaded on first use"
                            )
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(
                                .center
                            )
                        }

                        // Engine picker
                        Picker("Engine", selection: Binding(
                            get: { effectiveEngine },
                            set: { newEngine in
                                viewModel.selectedTranscriptEngine = newEngine
                                if newEngine == .whisper {
                                    return
                                }

                                if let selected = viewModel.selectedTranscriptLanguage {
                                    let resolved = resolvedLanguage(selected)
                                    let isSupported = SettingsViewModel.locales(for: newEngine).contains {
                                        $0.id == resolved
                                    }
                                    if !isSupported {
                                        viewModel.selectedTranscriptLanguage = nil
                                    }
                                }
                            }
                        )) {
                            ForEach(TranscriptEngine.allCases) { engine in
                                Label(engine.displayName, systemImage: engine.systemImage)
                                    .tag(engine)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.subheadline)

                        // Language picker (filtered by engine)
                        Picker("Language", selection: Binding(
                            get: {
                                if effectiveEngine == .whisper {
                                    return viewModel.selectedTranscriptLanguage ?? "auto"
                                }
                                return resolvedLanguage(viewModel.selectedTranscriptLanguage ?? viewModel.podcastLanguage)
                            },
                            set: { newValue in
                                if effectiveEngine == .whisper {
                                    viewModel.selectedTranscriptLanguage = (newValue == "auto") ? nil : newValue
                                } else {
                                    let defaultLocale = resolvedLanguage(viewModel.podcastLanguage)
                                    viewModel.selectedTranscriptLanguage = (newValue == defaultLocale) ? nil : newValue
                                }
                            }
                        )) {
                            ForEach(pickerLocales) { locale in
                                Text(locale.name).tag(locale.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.subheadline)

                        if effectiveEngine == .whisper {
                            Text("Auto-detect identifies the language automatically")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            Text("Apple Speech requires a model download per language")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        Button(action: { viewModel.generateTranscript() }) {
                            Label(
                                "Generate Transcript",
                                systemImage: "text.bubble"
                            )
                            .font(.subheadline)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if effectiveEngine == .yapServer {
                    // Yap can stream directly from the RSS URL — no download needed
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)
                        Text("Ready to Generate via Yap Server").font(.headline)
                        Text("The episode will be streamed directly to your yap server. No download required.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        // Engine picker
                        Picker("Engine", selection: Binding(
                            get: { effectiveEngine },
                            set: { newEngine in
                                viewModel.selectedTranscriptEngine = newEngine
                                if newEngine != .whisper, let selected = viewModel.selectedTranscriptLanguage {
                                    let resolved = resolvedLanguage(selected)
                                    if !SettingsViewModel.locales(for: newEngine).contains(where: { $0.id == resolved }) {
                                        viewModel.selectedTranscriptLanguage = nil
                                    }
                                }
                            }
                        )) {
                            ForEach(TranscriptEngine.allCases) { engine in
                                Label(engine.displayName, systemImage: engine.systemImage).tag(engine)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.subheadline)

                        // Language picker
                        Picker("Language", selection: Binding(
                            get: { resolvedLanguage(viewModel.selectedTranscriptLanguage ?? viewModel.podcastLanguage) },
                            set: { newValue in
                                let defaultLocale = resolvedLanguage(viewModel.podcastLanguage)
                                viewModel.selectedTranscriptLanguage = (newValue == defaultLocale) ? nil : newValue
                            }
                        )) {
                            ForEach(pickerLocales) { locale in
                                Text(locale.name).tag(locale.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.subheadline)

                        Button(action: { viewModel.generateTranscript() }) {
                            Label("Generate Transcript", systemImage: "text.bubble")
                                .font(.subheadline)
                                .padding(.horizontal, 20).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                        Text("Download Episode to Transcribe").font(.headline)
                        Text(
                            "You need to download the episode audio before generating a transcript."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        Button(action: { viewModel.startDownload() }) {
                            Label("Download Episode", systemImage: "arrow.down.circle")
                                .font(.subheadline)
                                .padding(.horizontal, 20).padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

            case .downloadingModel(let progress):
                VStack(spacing: 12) {
                    ProgressView(value: progress) {
                        Text("Downloading Speech Model...")
                            .font(.caption)
                    }
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                    Text("\(Int(progress * 100))%")
                        .font(.caption).foregroundStyle(.secondary)

                    Button("Cancel", role: .cancel) {
                        viewModel.cancelTranscript()
                    }
                    .buttonStyle(.bordered)
                }

            case .transcribing(let progress):
                VStack(spacing: 12) {
                    ProgressView(value: progress) {
                        Text("Generating Transcript (\(transcriptLanguageName))...")
                            .font(.caption)
                    }
                    .progressViewStyle(.linear)
                    .frame(width: 200)

                    Text("\(Int(progress * 100))%")
                        .font(.caption).foregroundStyle(.secondary)

                    Button("Cancel", role: .cancel) {
                        viewModel.cancelTranscript()
                    }
                    .buttonStyle(.bordered)
                }

            case .completed:
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.green)
                    Text("Transcript Ready").font(.headline)
                }

            case .error(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.red)
                    Text("Transcription Failed").font(.headline)
                    Text(message)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                        Button("Try Again") {
                            viewModel.generateTranscript()
                        }
                        .buttonStyle(.bordered)
                }
            }
        }
    }
}
