import SwiftData
import SwiftUI

/// Idle-state config UI: engine cards, language + options, recognition terms and
/// the primary generate/download action. Derived engine/language logic lives on
/// TranscriptCoordinator so this and TranscriptGeneratingView share one source.
struct TranscriptGenerateConfigView: View {
    @Bindable var viewModel: EpisodeDetailViewModel

    @Environment(\.modelContext) private var modelContext
    @State private var contextPodcast: PodcastInfoModel?
    @State private var showContextEditor = false

    private var effectiveEngine: TranscriptEngine { viewModel.transcript.effectiveEngine }

    /// Whether the current engine + audio state can generate without downloading first.
    private var canGenerate: Bool {
        viewModel.hasLocalAudio || effectiveEngine == .yapServer
    }

    var body: some View {
        VStack(spacing: 16) {
            header

            Divider()

            engineSelector

            // Generation options are only meaningful once audio is available
            // (or when streaming via Yap). When a download is required first,
            // keep the engine cards — so the user can switch to Yap and skip the
            // download — but hide the language/options noise behind the prompt.
            if canGenerate {
                optionsCard
                engineHint
                contextTermsSection
            }

            Divider()

            primaryActionView

            if canGenerate {
                privacyNote
            }
        }
        .onAppear(perform: loadContextPodcast)
    }

    // MARK: - Header
    //
    // When ready to generate, the engine cards already carry the visual weight —
    // so drop the oversized icon and show a slim title. Keep the big attention
    // icon only for the download-required / failed states.

    @ViewBuilder
    private var header: some View {
        if canGenerate {
            VStack(spacing: 4) {
                Text(headerTitle).font(.headline)
                Text(statusDescription)
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: headerIconName)
                    .font(.system(size: 44))
                    .foregroundStyle(headerIconColor)
                Text(headerTitle).font(.headline)
                Text(statusDescription)
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private var headerIconName: String {
        switch viewModel.downloadState {
        case .failed: return "exclamationmark.triangle.fill"
        case .downloading, .finishing: return "arrow.down.circle.fill"
        case .notDownloaded, .downloaded: return "arrow.down.circle"
        }
    }

    private var headerIconColor: Color {
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

    // MARK: - Engine selection (tappable cards)

    private var engineSelector: some View {
        VStack(spacing: 8) {
            ForEach(TranscriptEngine.allCases) { engine in
                engineCard(engine)
            }
        }
    }

    private func engineCard(_ engine: TranscriptEngine) -> some View {
        let selected = effectiveEngine == engine
        return Button {
            selectEngine(engine)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: engine.systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? .blue : .secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(engine.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if engine == .appleSpeech {
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                    Text(engineTagline(engine))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? .blue : Color.secondary.opacity(0.4))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.blue : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private func engineTagline(_ engine: TranscriptEngine) -> String {
        switch engine {
        case .appleSpeech: "Fastest · built-in · 50+ languages"
        case .whisper: "Most accurate · on-device"
        case .yapServer: "Offload to your own machine"
        }
    }

    /// Clears the selected language if a newly-picked non-Whisper engine doesn't
    /// support it.
    private func selectEngine(_ newEngine: TranscriptEngine) {
        viewModel.transcript.selectedTranscriptEngine = newEngine
        guard newEngine != .whisper, let selected = viewModel.transcript.selectedTranscriptLanguage else { return }
        let resolved = viewModel.transcript.resolvedLanguage(selected)
        if !SettingsViewModel.locales(for: newEngine).contains(where: { $0.id == resolved }) {
            viewModel.transcript.selectedTranscriptLanguage = nil
        }
    }

    // MARK: - Options card (language + split / music)

    @ViewBuilder
    private var optionsCard: some View {
        let settings = SubtitleSettingsManager.shared
        VStack(spacing: 0) {
            languagePicker
                .padding(.vertical, 6)
            // Split is a local Apple Speech optimization (parallel chunks) —
            // Yap and Whisper run their own pipeline, so it's Apple-Speech-only.
            if effectiveEngine == .appleSpeech {
                Divider()
                Toggle(isOn: Binding(
                    get: { settings.splitLongAudio },
                    set: { settings.splitLongAudio = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Split long audio")
                        Text("Transcribe long files in parallel chunks — faster.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            // Music detection (Yap forwards detect_music; Whisper has none).
            if effectiveEngine == .appleSpeech || effectiveEngine == .yapServer {
                Divider()
                Toggle(isOn: Binding(
                    get: { settings.enableMusicDetection },
                    set: { settings.enableMusicDetection = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Music detection")
                        Text("Mark music sections as [♪ Music] instead of mis-transcribing them.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }

    private var languagePicker: some View {
        Picker("Language", selection: Binding(
            get: {
                if effectiveEngine == .whisper {
                    return viewModel.transcript.selectedTranscriptLanguage ?? "auto"
                }
                if let selected = viewModel.transcript.selectedTranscriptLanguage {
                    return viewModel.transcript.resolvedLanguage(selected)
                }
                let lang = viewModel.podcastLanguage
                guard !lang.isEmpty else {
                    let deviceCode = Locale.current.language.languageCode?.identifier ?? "en"
                    return viewModel.transcript.resolvedLanguage(deviceCode)
                }
                return viewModel.transcript.resolvedLanguage(lang)
            },
            set: { newValue in
                if effectiveEngine == .whisper {
                    viewModel.transcript.selectedTranscriptLanguage = newValue == "auto" ? nil : newValue
                } else {
                    viewModel.transcript.selectedTranscriptLanguage = newValue
                }
            }
        )) {
            if effectiveEngine == .whisper {
                Text("Auto-detect").tag("auto")
            }
            ForEach(viewModel.transcript.pickerLocales) { locale in
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

    // MARK: - Primary action + privacy note

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

    /// Footnote reassuring the user that on-device engines keep audio local.
    /// Hidden for Yap Server, which streams the episode to a remote machine.
    @ViewBuilder
    private var privacyNote: some View {
        if effectiveEngine != .yapServer {
            Label("Runs privately on this device · no audio uploaded", systemImage: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
