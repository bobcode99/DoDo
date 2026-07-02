import SwiftUI

/// Live "generating transcript" UI: progress ring, a coarse pipeline, and the
/// active config chips. Presentational — driven only by values the coordinator
/// already publishes (state progress + real chunk part-progress).
struct TranscriptGeneratingView: View {
    let engine: TranscriptEngine
    let languageName: String
    /// True while the Whisper model is still downloading (before transcription).
    let isModelDownload: Bool
    let progress: Double
    /// Real chunk counts for the split Apple Speech path (nil otherwise).
    let partProgress: TranscriptPartProgress?
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
        isModelDownload
            ? "Downloading Speech Model…"
            : "Generating Transcript (\(languageName))…"
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
        let id = UUID()
        let title: String
        let detail: String?
        let state: StageState
    }

    /// ponytail: split/merge boundaries are approximated from the single progress
    /// value — only model-download and chunk part-progress are real events. Full
    /// per-phase fidelity would need the transcription service to emit phase
    /// markers up through the coordinator.
    private var stages: [Stage] {
        if engine == .whisper {
            return [
                Stage(title: "Download model", detail: nil,
                      state: isModelDownload ? .active : .done),
                Stage(title: "Transcribe", detail: nil,
                      state: isModelDownload ? .pending : (progress >= 0.99 ? .done : .active)),
                Stage(title: "Finalize & align", detail: nil,
                      state: progress >= 0.99 ? .active : .pending),
            ]
        }
        // Apple Speech / Yap
        let partDetail = partProgress.map {
            "Part \(min($0.completed + 1, $0.total))/\($0.total)"
        }
        return [
            Stage(title: "Prepare audio", detail: nil,
                  state: (progress > 0.02 || partProgress != nil) ? .done : .active),
            Stage(title: "Transcribe", detail: partDetail,
                  state: progress >= 0.98 ? .done : .active),
            Stage(title: "Merge & align", detail: nil,
                  state: progress >= 0.98 ? .active : .pending),
        ]
    }

    private var pipeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(stages) { stage in
                HStack(spacing: 11) {
                    stageIcon(stage.state)
                        .frame(width: 20)
                    Text(stage.title)
                        .font(.subheadline)
                        .foregroundStyle(stage.state == .pending ? .secondary : .primary)
                    Spacer(minLength: 0)
                    if let detail = stage.detail {
                        Text(detail)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(stage.state == .pending ? 0.55 : 1)
            }
        }
        .frame(maxWidth: 300)
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
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
