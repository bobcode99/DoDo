//
//  TranscriptTranslationManagerTests.swift
//  PodcastAnalyzerTests
//
//  A transcript translation is an app-wide job keyed by episode, so it keeps
//  running after the transcript page that started it goes away. These drive
//  the manager through a fake translator: on the Simulator the Translation
//  framework reports every language pair unsupported.
//

import Foundation
import Synchronization
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Transcript translation jobs")
struct TranscriptTranslationManagerTests {

    private static let key = EpisodeKeyUtils.makeKey(podcastTitle: "Show", episodeTitle: "Episode")
    private static let source = Locale.Language(identifier: "zh-Hant")
    private static let segments = [
        TranscriptSegment(id: 0, startTime: 0, endTime: 1, text: "早安"),
        TranscriptSegment(id: 1, startTime: 1, endTime: 2, text: "晚安"),
    ]

    private func start(
        _ manager: TranscriptTranslationManager, target: TranslationTargetLanguage = .english
    ) {
        manager.translate(
            Self.segments, episodeKey: Self.key, episodeTitle: "Episode", podcastTitle: "Show",
            source: Self.source, target: target
        )
    }

    private func status(_ manager: TranscriptTranslationManager) -> TranslationStatus? {
        manager.jobs[Self.key]?.status
    }

    /// The job runs in its own task; give it a bounded chance to get there.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("A job finishes with translated segments with no page or coordinator alive")
    func completesWithoutAView() async throws {
        let manager = TranscriptTranslationManager { texts, _, _ in
            AsyncThrowingStream { continuation in
                // Out of order on purpose: results are matched by index, not arrival.
                for (index, text) in texts.enumerated().reversed() {
                    continuation.yield((index, "EN \(text)"))
                }
                continuation.finish()
            }
        }

        start(manager)
        try await waitUntil { status(manager) == .completed }

        let job = try #require(manager.jobs[Self.key])
        #expect(job.status == .completed)
        #expect(job.target == .english)
        #expect(job.segments?.map(\.text) == ["早安", "晚安"])
        #expect(job.segments?.map(\.translatedText) == ["EN 早安", "EN 晚安"])
    }

    @Test("Progress reaches the segment total before the job completes")
    func progressReachesTotal() async throws {
        let fake = ControlledTranslator()
        let manager = TranscriptTranslationManager(translator: fake.translator)

        start(manager)
        #expect(status(manager) == .translating(progress: 0, completed: 0, total: 2))

        fake.continuation(0).yield((0, "Good morning"))
        fake.continuation(0).yield((1, "Good night"))
        let full = TranslationStatus.translating(progress: 1, completed: 2, total: 2)
        try await waitUntil { status(manager) == full }
        #expect(status(manager) == full)

        fake.continuation(0).finish()
        try await waitUntil { status(manager) == .completed }
        #expect(status(manager) == .completed)
    }

    @Test("Asking again for the running target starts nothing; a new target replaces the job")
    func sameTargetIsNoOpNewTargetReplaces() async throws {
        let fake = ControlledTranslator()
        let manager = TranscriptTranslationManager(translator: fake.translator)

        start(manager, target: .english)
        start(manager, target: .english)
        #expect(fake.callCount == 1)

        start(manager, target: .japanese)
        #expect(fake.callCount == 2)
        #expect(manager.jobs[Self.key]?.target == .japanese)

        fake.continuation(0).yield((0, "stale English"))
        fake.continuation(0).finish()
        fake.continuation(1).yield((0, "おはよう"))
        fake.continuation(1).yield((1, "おやすみ"))
        fake.continuation(1).finish()
        try await waitUntil { status(manager) == .completed }

        let job = try #require(manager.jobs[Self.key])
        #expect(job.target == .japanese)
        #expect(job.segments?.map(\.translatedText) == ["おはよう", "おやすみ"])
    }

    @Test("A replaced job's error doesn't fail the job that replaced it")
    func replacedJobErrorIsIgnored() async throws {
        let fake = ControlledTranslator()
        let manager = TranscriptTranslationManager(translator: fake.translator)

        start(manager, target: .english)
        // Buffered before the replacement cancels the first job's task.
        fake.continuation(0).finish(throwing: UnsupportedPair())
        start(manager, target: .japanese)
        try await Task.sleep(for: .milliseconds(50))
        #expect(status(manager) == .translating(progress: 0, completed: 0, total: 2))

        fake.continuation(1).yield((0, "おはよう"))
        fake.continuation(1).yield((1, "おやすみ"))
        fake.continuation(1).finish()
        try await waitUntil { status(manager) == .completed }
        #expect(status(manager) == .completed)
    }

    @Test("A translator error fails the job with the error's message")
    func translatorErrorFails() async throws {
        let manager = TranscriptTranslationManager { _, _, _ in
            AsyncThrowingStream { $0.finish(throwing: UnsupportedPair()) }
        }

        start(manager)
        try await waitUntil { status(manager)?.isTranslating == false }

        #expect(status(manager) == .failed("Language pair unsupported"))
    }

    @Test("Cancelling removes the job and drops its late results")
    func cancelRemovesJob() async throws {
        let fake = ControlledTranslator()
        let manager = TranscriptTranslationManager(translator: fake.translator)

        start(manager)
        manager.cancel(episodeKey: Self.key)
        #expect(manager.jobs[Self.key] == nil)

        fake.continuation(0).yield((0, "late"))
        fake.continuation(0).yield((1, "late"))
        fake.continuation(0).finish()
        try await Task.sleep(for: .milliseconds(50))
        #expect(manager.jobs[Self.key] == nil)
    }
}

private struct UnsupportedPair: LocalizedError {
    var errorDescription: String? { "Language pair unsupported" }
}

/// Hands each request's stream to the test, so the test decides when results
/// arrive and can count how many translations were started.
private final class ControlledTranslator: Sendable {
    private let continuations = Mutex<[AsyncThrowingStream<(Int, String), Error>.Continuation]>([])

    var callCount: Int { continuations.withLock { $0.count } }

    func continuation(_ call: Int) -> AsyncThrowingStream<(Int, String), Error>.Continuation {
        continuations.withLock { $0[call] }
    }

    var translator: TranscriptTranslationManager.BatchTranslator {
        { [self] _, _, _ in
            let (stream, continuation) = AsyncThrowingStream<(Int, String), Error>.makeStream()
            continuations.withLock { $0.append(continuation) }
            return stream
        }
    }
}
