//
//  TranscriptStallTimeoutTests.swift
//  PodcastAnalyzerTests
//
//  The local-engine stall watchdog: a transcription that stops reporting
//  progress fails, but time the app spends suspended never counts toward it.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Transcript stall watchdog")
struct TranscriptStallTimeoutTests {

    private actor BoolBox {
        var value: Bool
        init(_ value: Bool) { self.value = value }
        func set(_ newValue: Bool) { value = newValue }
    }

    private enum Outcome: Equatable { case finished, stalled, otherError }

    private func consume(_ stream: AsyncThrowingStream<Int, Error>) async -> Outcome {
        do {
            for try await _ in stream {}
            return .finished
        } catch {
            return error.localizedDescription.contains("stalled") ? .stalled : .otherError
        }
    }

    @Test("A silent engine fails as stalled while the app is active")
    func silentWhileActiveStalls() async {
        let (source, continuation) = AsyncThrowingStream.makeStream(of: Int.self)
        let guarded = TranscriptManager.withStallTimeout(
            source, stallSeconds: 0.2, label: "Apple Speech",
            tick: .milliseconds(20), isActive: { true }
        )
        #expect(await consume(guarded) == .stalled)
        continuation.finish()
    }

    @Test("Time spent inactive doesn't count toward a stall")
    func inactiveTimeDoesNotCount() async throws {
        let (source, continuation) = AsyncThrowingStream.makeStream(of: Int.self)
        let flag = BoolBox(false)
        let guarded = TranscriptManager.withStallTimeout(
            source, stallSeconds: 0.2, label: "Apple Speech",
            tick: .milliseconds(20), isActive: { await flag.value }
        )
        let done = BoolBox(false)
        let run = Task {
            let outcome = await consume(guarded)
            await done.set(true)
            return outcome
        }

        // Five times the stall limit while "suspended", with no progress at all.
        try await Task.sleep(for: .seconds(1))
        #expect(await done.value == false, "suspended time must not trip the watchdog")

        // Back in the foreground and still silent: now it trips.
        await flag.set(true)
        #expect(await run.value == .stalled)
        continuation.finish()
    }

    @Test("Progress flowing through finishes normally")
    func progressPassesThrough() async {
        let (source, continuation) = AsyncThrowingStream.makeStream(of: Int.self)
        let guarded = TranscriptManager.withStallTimeout(
            source, stallSeconds: 0.2, label: "Apple Speech",
            tick: .milliseconds(20), isActive: { true }
        )
        for i in 0..<5 { continuation.yield(i) }
        continuation.finish()

        var received: [Int] = []
        do {
            for try await value in guarded { received.append(value) }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(received == [0, 1, 2, 3, 4])
    }
}
