import SwiftUI

/// Live "generating transcript" UI: progress ring, the real pipeline stages, and
/// the active config chips. Stages are driven by the actual `TranscriptionPhase`
/// the service emits (Apple Speech) plus model-download state — not guessed from
/// the percentage. Yap has no phase stream, so its steps derive from progress.
struct TranscriptGeneratingView: View {
    let engine: TranscriptEngine
    let languageName: String
    /// True while the engine's assets are still downloading (Whisper model or
    /// Apple Speech per-language assets) — i.e. the `.downloadingModel` state.
    let isDownloadingAssets: Bool
    let progress: Double
    /// Real chunk counts for the split Apple Speech path (nil otherwise).
    let partProgress: TranscriptPartProgress?
    /// Real pipeline step from the service (nil for Yap / before first emit).
    let phase: TranscriptionPhase?
    let onCancel: () -> Void

    private var settings: SubtitleSettingsManager { .shared }

    var body: some View {
        VStack(spacing: 18) {
            ring
            Text(headline)
                .font(.headline)
                .multilineTextAlignment(.center)
            pipeline
            chips
            Button("Cancel", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(headline), \(Int(progress * 100)) percent"))
    }

    private var headline: String {
        if isDownloadingAssets {
            return engine == .whisper ? "Downloading Model…" : "Downloading Assets…"
        }
        return "Generating Transcript (\(languageName))…"
    }

    // MARK: - Ring

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(progress, 0.001))
                .stroke(.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)
            Text("\(Int(progress * 100))%")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(width: 140, height: 140)
    }

    // MARK: - Pipeline

    private enum StageState { case done, active, pending }

    private struct Stage: Identifiable {
        // Stable identity: titles are unique per pipeline. A fresh UUID here would
        // change every body evaluation and make ForEach rebuild all rows per tick.
        var id: String { title }
        let title: String
        let detail: String?
        let state: StageState
        /// Show the per-chunk bar strip under this stage (transcribe step only).
        var showsChunks: Bool = false
    }

    private var partDetail: String? {
        partProgress.map { "Part \(min($0.completed + 1, $0.total))/\($0.total)" }
    }

    private var stages: [Stage] {
        switch engine {
        case .appleSpeech: return appleSpeechStages
        case .whisper: return whisperStages
        case .yapServer: return yapStages
        }
    }

    /// Apple Speech: real phases from the service (prepare/split/transcribe/merge)
    /// plus the asset-download state ahead of them.
    private var appleSpeechStages: [Stage] {
        let merging = phase == .merging || progress >= 1
        let transcribing = phase == .transcribing && !merging
        // "Splitting" covers prepare + split, before any chunk transcription.
        let splitting = !isDownloadingAssets && !transcribing && !merging

        func s(_ done: Bool, _ active: Bool) -> StageState {
            done ? .done : (active ? .active : .pending)
        }
        return [
            Stage(title: "Download assets", detail: nil,
                  state: isDownloadingAssets ? .active : .done),
            Stage(title: "Prepare & split audio", detail: nil,
                  state: isDownloadingAssets ? .pending : s(transcribing || merging, splitting)),
            Stage(title: "Transcribe", detail: partDetail,
                  state: s(merging, transcribing),
                  showsChunks: transcribing && partProgress != nil),
            Stage(title: "Merge & align", detail: nil,
                  state: s(progress >= 1, merging)),
        ]
    }

    private var whisperStages: [Stage] {
        [
            Stage(title: "Download model", detail: nil,
                  state: isDownloadingAssets ? .active : .done),
            Stage(title: "Transcribe", detail: nil,
                  state: isDownloadingAssets ? .pending : (progress >= 0.99 ? .done : .active)),
            Stage(title: "Finalize & align", detail: nil,
                  state: progress >= 0.99 ? .active : .pending),
        ]
    }

    private var yapStages: [Stage] {
        [
            Stage(title: "Upload to server", detail: nil,
                  state: progress > 0 ? .done : .active),
            Stage(title: "Transcribe on server", detail: nil,
                  state: progress >= 0.99 ? .done : .active),
            Stage(title: "Finalize", detail: nil,
                  state: progress >= 0.99 ? .active : .pending),
        ]
    }

    private var pipeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(stages) { stage in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 11) {
                        stageIcon(stage.state).frame(width: 20)
                        Text(stage.title)
                            .font(.subheadline)
                            .fontWeight(stage.state == .active ? .semibold : .regular)
                            .foregroundStyle(stage.state == .pending ? .secondary : .primary)
                        Spacer(minLength: 0)
                        if let detail = stage.detail {
                            Text(detail)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.blue)
                        }
                    }
                    if stage.showsChunks, let parts = partProgress {
                        chunkBar(parts).padding(.leading, 31)
                    }
                }
                .opacity(stage.state == .pending ? 0.55 : 1)
            }
        }
        .frame(maxWidth: 300)
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
    }

    /// Segmented bar mirroring the design: one cell per chunk, filled as parts
    /// complete, the in-flight cell tinted lighter.
    private func chunkBar(_ parts: TranscriptPartProgress) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<max(parts.total, 1), id: \.self) { i in
                Capsule()
                    .fill(chunkColor(index: i, completed: parts.completed))
                    .frame(height: 5)
            }
        }
    }

    private func chunkColor(index: Int, completed: Int) -> Color {
        if index < completed { return .blue }
        if index == completed { return .blue.opacity(0.4) }
        return Color.secondary.opacity(0.18)
    }

    @ViewBuilder
    private func stageIcon(_ state: StageState) -> some View {
        switch state {
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
        case .active:
            ProgressView().controlSize(.small)
        case .pending:
            Image(systemName: "circle").foregroundStyle(Color.secondary.opacity(0.5))
        }
    }

    // MARK: - Config chips

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ConfigChip(icon: engine.systemImage, label: engine.displayName, tint: .blue)
                ConfigChip(icon: "globe", label: languageName, tint: .teal)

                switch engine {
                case .appleSpeech:
                    ConfigChip(
                        icon: "rectangle.split.3x1",
                        label: settings.splitLongAudio ? "Split: On" : "Split: Off",
                        tint: settings.splitLongAudio ? .green : .secondary)
                    musicChip
                case .yapServer:
                    musicChip
                case .whisper:
                    ConfigChip(
                        icon: "cpu",
                        label: WhisperModelManager.shared.selectedModel.displayName,
                        tint: .indigo)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: 320)
    }

    private var musicChip: ConfigChip {
        ConfigChip(
            icon: "music.note",
            label: settings.enableMusicDetection
                ? "Music: \(settings.musicDetectionSensitivity.displayName)"
                : "Music: Off",
            tint: settings.enableMusicDetection ? .purple : .secondary)
    }
}
