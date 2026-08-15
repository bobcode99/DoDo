//
//  CloudAnalysisJobCoordinator.swift
//  PodcastAnalyzer
//
//  Owns in-flight cloud AI analysis jobs so they survive view tear-down.
//  EpisodeDetailViewModel delegates `generateCloudAnalysis` here and reads
//  the live job snapshot via computed properties; if the user pops the
//  detail view (or navigates away from a macOS AI page) while a streaming
//  Ollama / Claude / Gemini / OpenAI request is running, the work keeps
//  going, saves to SwiftData on completion, and the same episode re-opened
//  reattaches to the running job — the streaming UI resumes mid-flight.
//

import Foundation
import OSLog
import SwiftData

#if os(iOS)
import UIKit
#endif

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "CloudAnalysisJobCoordinator")

extension Notification.Name {
    /// Posted when a coordinator-owned analysis finishes (success or error) and the
    /// SwiftData row has been written. UserInfo: `["audioURL": String]`.
    static let cloudAnalysisJobFinished = Notification.Name("cloudAnalysisJobFinished")
}

@MainActor
@Observable
final class CloudAnalysisJobCoordinator {
    static let shared = CloudAnalysisJobCoordinator()

    /// Live snapshot of an in-flight job. The view model exposes computed
    /// properties that read these fields, so SwiftUI re-renders automatically
    /// as the streaming Task mutates the dictionary.
    struct JobSnapshot {
        var state: AnalysisState
        var streamingText: String
        var currentType: CloudAnalysisType
        var isStreaming: Bool
        /// When the job started, so the UI can show elapsed time — a long
        /// request is otherwise indistinguishable from a hung one.
        var startedAt: Date = Date()
        /// Identifies this run. Cancelling a Task does not drop callbacks it
        /// already enqueued, so a restart on the same key must not be written
        /// to by the run it replaced.
        var runID: UUID = UUID()
    }

    /// Keyed by `PodcastEpisodeInfo.audioURL`. The view model passes the same key
    /// at start time and when reading back, so reopening the same episode finds
    /// its running job.
    private(set) var jobs: [String: JobSnapshot] = [:]

    /// Detached owner refs so we can cancel on explicit request. The job
    /// closure already keeps itself alive — these refs are *only* for cancellation.
    @ObservationIgnored
    private var tasks: [String: Task<Void, Never>] = [:]

    private init() {}

    func snapshot(for audioURL: String) -> JobSnapshot? {
        jobs[audioURL]
    }

    func isRunning(audioURL: String) -> Bool {
        jobs[audioURL]?.isStreaming == true
    }

    /// Whether `runID` is still the streaming job on this key — the gate every
    /// late callback has to pass before it may write.
    private func isLive(_ audioURL: String, _ runID: UUID) -> Bool {
        guard let job = jobs[audioURL] else { return false }
        return job.isStreaming && job.runID == runID
    }

    /// Start (or restart) an analysis for `audioURL`. Cancels any existing
    /// job for the same key — matches the previous `cloudAnalysisTask?.cancel()`
    /// behavior in `EpisodeDetailViewModel.generateCloudAnalysis`.
    func startAnalysis(
        audioURL: String,
        transcript: String,
        transcriptSegments: [QuotesFinder.Segment],
        episodeTitle: String,
        podcastTitle: String,
        type: CloudAnalysisType,
        podcastLanguage: String?,
        formatHint: String?,
        modelContext: ModelContext
    ) {
        tasks[audioURL]?.cancel()

        let snapshot = JobSnapshot(
            state: .analyzing(progress: 0, message: "Preparing..."),
            streamingText: "",
            currentType: type,
            isStreaming: true
        )
        jobs[audioURL] = snapshot
        let runID = snapshot.runID

        tasks[audioURL] = Task { [weak self] in
            // iOS background grace window. Same wrapping the view model previously
            // applied; kept here so the survival semantics live with the owner.
            #if os(iOS)
            var bgTaskID: UIBackgroundTaskIdentifier = .invalid
            bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "CloudAnalysisCoordinator") {
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                    bgTaskID = .invalid
                }
            }
            defer {
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
            #endif

            do {
                let result = try await CloudAIService.shared.analyzeTranscriptStreaming(
                    transcript,
                    episodeTitle: episodeTitle,
                    podcastTitle: podcastTitle,
                    analysisType: type,
                    podcastLanguage: podcastLanguage,
                    formatHint: formatHint,
                    transcriptSegments: transcriptSegments,
                    onChunk: { [weak self] text in
                        Task { @MainActor in
                            guard self?.isLive(audioURL, runID) == true else { return }
                            self?.jobs[audioURL]?.streamingText = text
                        }
                    },
                    // Both callbacks hop to the main actor, so an update emitted
                    // just before the request returns can land *after* the
                    // `.completed` snapshot below. Dropping updates once the job
                    // stops streaming keeps a late "Formatting result..." from
                    // resurrecting the progress card and stranding it forever.
                    progressCallback: { [weak self] message, progress in
                        Task { @MainActor in
                            guard self?.isLive(audioURL, runID) == true else { return }
                            self?.jobs[audioURL]?.state = .analyzing(progress: progress, message: message)
                        }
                    }
                )

                guard let self, self.isLive(audioURL, runID) else { return }

                // Persist the result before flipping state to .completed so any
                // observer reading SwiftData after seeing .completed sees the row.
                self.saveToSwiftData(
                    result: result,
                    audioURL: audioURL,
                    episodeTitle: episodeTitle,
                    podcastTitle: podcastTitle,
                    type: type,
                    context: modelContext
                )

                // Same runID: the drop check below must recognise this as the
                // run it started, not a newer one.
                self.jobs[audioURL] = JobSnapshot(
                    state: .completed,
                    streamingText: "",
                    currentType: type,
                    isStreaming: false,
                    runID: runID
                )

                NotificationCenter.default.post(
                    name: .cloudAnalysisJobFinished,
                    object: nil,
                    userInfo: ["audioURL": audioURL]
                )

                // Drop the snapshot after a short delay so view models that
                // re-attach right at completion still observe `.completed`,
                // then fall through to the SwiftData-backed result card.
                let dropDelay: Duration = .seconds(3)
                try? await Task.sleep(for: dropDelay)
                if self.jobs[audioURL]?.runID == runID, self.jobs[audioURL]?.state == .completed {
                    self.jobs.removeValue(forKey: audioURL)
                    self.tasks.removeValue(forKey: audioURL)
                }

                logger.info("Cloud analysis finished for \(audioURL, privacy: .private)")
            } catch {
                guard let self, self.isLive(audioURL, runID) else { return }
                self.jobs[audioURL] = JobSnapshot(
                    state: .error(error.localizedDescription),
                    streamingText: "",
                    currentType: type,
                    isStreaming: false,
                    runID: runID
                )
                NotificationCenter.default.post(
                    name: .cloudAnalysisJobFinished,
                    object: nil,
                    userInfo: ["audioURL": audioURL]
                )
                logger.error("Cloud analysis failed for \(audioURL, privacy: .private): \(error.localizedDescription)")
            }
        }
    }

    /// Cancel the job for `audioURL`. The snapshot is dropped so the view falls
    /// back to its idle / SwiftData-cached state.
    func cancel(audioURL: String) {
        tasks[audioURL]?.cancel()
        tasks.removeValue(forKey: audioURL)
        jobs.removeValue(forKey: audioURL)
    }

    // MARK: - SwiftData Persistence

    private func saveToSwiftData(
        result: CloudAnalysisResult,
        audioURL: String,
        episodeTitle: String,
        podcastTitle: String,
        type: CloudAnalysisType,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<EpisodeAIAnalysis>(
            predicate: #Predicate { $0.episodeAudioURL == audioURL }
        )

        do {
            let existing = try context.fetch(descriptor)
            let model: EpisodeAIAnalysis
            if let first = existing.first {
                model = first
            } else {
                model = EpisodeAIAnalysis(
                    episodeAudioURL: audioURL,
                    episodeTitle: episodeTitle,
                    podcastTitle: podcastTitle
                )
                context.insert(model)
            }

            switch type {
            case .analysis:
                model.parsedAnalysis = result.parsedAnalysis
                // Keep the verbatim reply either way: when the JSON does not
                // decode it is the only thing left to show, and previously it
                // was dropped here — the run looked successful but empty.
                model.rawResponse = result.content
                model.provider = result.provider.rawValue
                model.model = result.model
                model.generatedAt = result.timestamp
            }
            model.updatedAt = Date()
            try context.save()
        } catch {
            logger.error("Coordinator save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
