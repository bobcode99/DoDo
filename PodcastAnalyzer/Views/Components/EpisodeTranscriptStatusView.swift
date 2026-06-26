
import SwiftData
import SwiftUI

struct EpisodeTranscriptStatusView: View {
    @Bindable var viewModel: EpisodeDetailViewModel

    @Environment(\.modelContext) private var modelContext
    @State private var contextPodcast: PodcastInfoModel?
    @State private var showContextEditor = false

    private var effectiveEngine: TranscriptEngine {
        viewModel.transcript.selectedTranscriptEngine ?? TranscriptEngine(
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
        if effectiveEngine == .whisper, viewModel.transcript.selectedTranscriptLanguage == nil {
            if let detected = viewModel.transcript.transcriptDetectedLanguage {
                let name = pickerLocales.first { $0.id == detected }?.name
                    ?? Locale.current.localizedString(forLanguageCode: detected)
                    ?? detected
                return name
            }
            return "Auto-detect"
        }
        let code = viewModel.transcript.selectedTranscriptLanguage ?? viewModel.podcastLanguage
        return pickerLocales.first { $0.id == resolvedLanguage(code) }?.name ?? code
    }

    /// Whether the current engine + audio state can generate without downloading first.
    private var canGenerate: Bool {
        viewModel.hasLocalAudio || effectiveEngine == .yapServer
    }

    var body: some View {
        switch viewModel.transcript.transcriptState {
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
        if viewModel.transcript.hasRSSTranscriptAvailable {
            rssAvailableView
        } else if viewModel.transcript.isDownloadingRSSTranscript {
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
                viewModel.transcript.downloadRSSTranscript()
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
                Image(systemName: headerIconName)
                    .font(.system(size: 48))
                    .foregroundStyle(headerIconColor)
                Text(headerTitle)
                    .font(.headline)
                Text(statusDescription)
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            Divider()

            // Engine picker
            enginePicker

            languagePicker

            engineHint

            contextTermsSection

            Divider()

            // Primary action
            primaryActionView
        }
        .onAppear(perform: loadContextPodcast)
    }

    // MARK: - Recognition terms (Apple Speech contextual strings)

    @ViewBuilder
    private var contextTermsSection: some View {
        if effectiveEngine == .appleSpeech, let podcast = contextPodcast {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Recognition Terms", systemImage: "character.book.closed")
                        .font(.subheadline)
                    Spacer()
                    Button(podcast.transcriptionTerms.isEmpty ? "Add" : "Edit") {
                        showContextEditor = true
                    }
                    .font(.caption)
                }
                if podcast.transcriptionTerms.isEmpty {
                    Text("Add host/guest names & jargon so they're transcribed correctly.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            ForEach(podcast.transcriptionTerms, id: \.self) { term in
                                Text(term)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial, in: Capsule())
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: $showContextEditor) {
                NavigationStack {
                    TranscriptContextEditorView(podcast: podcast)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showContextEditor = false }
                            }
                        }
                }
            }
        }
    }

    private func loadContextPodcast() {
        let title = viewModel.podcastTitle
        guard !title.isEmpty else { return }
        var descriptor = FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.title == title }
        )
        descriptor.fetchLimit = 1
        contextPodcast = try? modelContext.fetch(descriptor).first
    }

    @ViewBuilder
    private var primaryActionView: some View {
        if canGenerate {
            Button(action: { viewModel.transcript.generateTranscript() }) {
                Label("Generate Transcript", systemImage: "text.bubble")
                    .font(.subheadline)
                    .padding(.horizontal, 20).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        } else {
            DownloadActionView(viewModel: viewModel)
        }
    }

    private var headerIconName: String {
        if canGenerate { return "waveform" }
        switch viewModel.downloadState {
        case .failed: return "exclamationmark.triangle.fill"
        case .downloading, .finishing: return "arrow.down.circle.fill"
        case .notDownloaded, .downloaded: return "arrow.down.circle"
        }
    }

    private var headerIconColor: Color {
        if canGenerate { return .blue }
        switch viewModel.downloadState {
        case .failed: return .red
        case .downloading, .finishing: return .blue
        case .notDownloaded, .downloaded: return .secondary
        }
    }

    private var headerTitle: String {
        if canGenerate { return "Ready to Generate" }
        switch viewModel.downloadState {
        case .downloading: return "Downloading Episode"
        case .finishing: return "Finalizing Download"
        case .failed: return "Download Failed"
        case .notDownloaded, .downloaded: return "Download Required"
        }
    }

    private var statusDescription: String {
        if canGenerate {
            if !viewModel.transcript.isModelReady && effectiveEngine == .whisper {
                return "Speech recognition model will be downloaded on first use."
            }
            if effectiveEngine == .yapServer && !viewModel.hasLocalAudio {
                return "The episode will be streamed directly to your Yap server."
            }
            return "Select an engine and language, then tap Generate."
        }
        switch viewModel.downloadState {
        case .downloading:
            return "Downloading episode audio. You can generate the transcript once this finishes."
        case .finishing:
            return "Finalizing the downloaded file…"
        case .failed:
            return "Download failed. Retry, or switch to Yap Server to stream instead."
        case .notDownloaded, .downloaded:
            return "Download the episode audio to generate a transcript locally, or switch to Yap Server to stream instead."
        }
    }

    private var enginePicker: some View {
        Picker("Engine", selection: Binding(
            get: { effectiveEngine },
            set: { newEngine in
                viewModel.transcript.selectedTranscriptEngine = newEngine
                guard newEngine != .whisper, let selected = viewModel.transcript.selectedTranscriptLanguage else { return }
                let resolved = resolvedLanguage(selected)
                if !SettingsViewModel.locales(for: newEngine).contains(where: { $0.id == resolved }) {
                    viewModel.transcript.selectedTranscriptLanguage = nil
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
                    return viewModel.transcript.selectedTranscriptLanguage ?? "auto"
                }
                if let selected = viewModel.transcript.selectedTranscriptLanguage {
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
                    viewModel.transcript.selectedTranscriptLanguage = newValue == "auto" ? nil : newValue
                } else {
                    // Always store the explicit selection — never nil-optimize.
                    // Nil-optimizing caused the picker to show "zh-tw" (first locale,
                    // accidental match for empty podcastLanguage) while selectedTranscriptLanguage
                    // remained nil, so generateTranscript() fell back to getPodcastLanguage() → "en".
                    viewModel.transcript.selectedTranscriptLanguage = newValue
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

            Button("Cancel", role: .cancel) { viewModel.transcript.cancelTranscript() }
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
                viewModel.transcript.transcriptState = .idle
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }
}

/// Isolated subview so that the high-frequency `downloadState` observation only
/// invalidates this small block — not the engine/language pickers above it.
private struct DownloadActionView: View {
    @Bindable var viewModel: EpisodeDetailViewModel

    var body: some View {
        switch viewModel.downloadState {
        case .downloading(let progress):
            progressRow(progress: progress)
        case .finishing:
            finishingRow
        case .failed(let error):
            failedRow(error: error)
        case .notDownloaded, .downloaded:
            Button(action: { viewModel.startDownload() }) {
                Label("Download Episode", systemImage: "arrow.down.circle")
                    .font(.subheadline)
                    .padding(.horizontal, 20).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func progressRow(progress: Double) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Downloading…")
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Button("Cancel", role: .cancel) { viewModel.cancelDownload() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: 320)
    }

    private var finishingRow: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Finalizing download…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func failedRow(error: String) -> some View {
        VStack(spacing: 8) {
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button(action: { viewModel.startDownload() }) {
                Label("Retry Download", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .padding(.horizontal, 20).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
