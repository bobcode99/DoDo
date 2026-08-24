//
//  TranscriptDownloadStateTests.swift
//  PodcastAnalyzerTests
//
//  The transcript button on an episode row reads its whole appearance off this
//  state, and each value means something different to the user: "Transcript"
//  (fetch the publisher's), a spinner, a checkmark, or nothing at all. The
//  network leg needs a server, but the decision about which state an episode is
//  in — given what the feed advertised and what is on disk — does not.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Transcript download state")
struct TranscriptDownloadStateTests {

    private let service = TranscriptDownloadService.shared

    /// Titles nothing has ever written a transcript for, so the on-disk check
    /// is a genuine miss rather than a leftover from another test.
    private func uniqueTitles() -> (podcast: String, episode: String) {
        let id = UUID().uuidString
        return ("TranscriptDownloadStateTests \(id)", "Episode \(id)")
    }

    // MARK: - State classification

    @Test("Only the available state reports itself as available")
    func availableIsExclusive() {
        #expect(TranscriptDownloadState.available(url: "https://example.com/1.vtt",
                                                  type: "text/vtt").isAvailable)
        #expect(TranscriptDownloadState.notAvailable.isAvailable == false)
        #expect(TranscriptDownloadState.downloading(progress: 0.5).isAvailable == false)
        #expect(TranscriptDownloadState.downloaded.isAvailable == false)
        #expect(TranscriptDownloadState.failed(error: "boom").isAvailable == false)
    }

    @Test("Only the downloading state reports itself as downloading")
    func downloadingIsExclusive() {
        #expect(TranscriptDownloadState.downloading(progress: 0).isDownloading)
        #expect(TranscriptDownloadState.downloading(progress: 1).isDownloading)
        #expect(TranscriptDownloadState.downloaded.isDownloading == false)
        #expect(TranscriptDownloadState.notAvailable.isDownloading == false)
    }

    @Test("Only the downloaded state reports itself as downloaded")
    func downloadedIsExclusive() {
        #expect(TranscriptDownloadState.downloaded.isDownloaded)
        #expect(TranscriptDownloadState.downloading(progress: 1).isDownloaded == false)
        #expect(TranscriptDownloadState.available(url: "u", type: "t").isDownloaded == false)
        #expect(TranscriptDownloadState.failed(error: "boom").isDownloaded == false)
    }

    @Test("States compare by their payload, so a progress tick is a real change")
    func statesCompareByPayload() {
        #expect(TranscriptDownloadState.downloading(progress: 0.5)
                == .downloading(progress: 0.5))
        #expect(TranscriptDownloadState.downloading(progress: 0.5)
                != .downloading(progress: 0.6))
        #expect(TranscriptDownloadState.available(url: "a", type: "text/vtt")
                != .available(url: "b", type: "text/vtt"))
        #expect(TranscriptDownloadState.failed(error: "one") != .failed(error: "two"))
    }

    // MARK: - Deciding the state

    @Test("An episode whose feed advertises a transcript offers it for download")
    func advertisedTranscriptIsAvailable() async {
        let (podcast, episode) = uniqueTitles()

        let state = await service.getDownloadState(
            episodeTitle: episode, podcastTitle: podcast,
            transcriptURL: "https://example.com/1.vtt", transcriptType: "text/vtt")

        #expect(state == .available(url: "https://example.com/1.vtt", type: "text/vtt"))
    }

    @Test("An episode with no transcript in its feed offers nothing")
    func noTranscriptInFeed() async {
        let (podcast, episode) = uniqueTitles()

        let state = await service.getDownloadState(
            episodeTitle: episode, podcastTitle: podcast,
            transcriptURL: nil, transcriptType: nil)

        #expect(state == .notAvailable)
    }

    @Test("A transcript URL with no type is not offered, since the format is unknown")
    func urlWithoutTypeIsNotOffered() async {
        let (podcast, episode) = uniqueTitles()

        let state = await service.getDownloadState(
            episodeTitle: episode, podcastTitle: podcast,
            transcriptURL: "https://example.com/1.vtt", transcriptType: nil)

        #expect(state == .notAvailable)
    }

    // MARK: - Errors

    @Test("Every failure carries a message the UI can show")
    func errorsAreDescribed() {
        // Deliberately a loop rather than `@Test(arguments:)`: the error type
        // wraps an `any Error` in `.saveFailed`, so it isn't `Sendable` and
        // can't be used as a test argument.
        let errors: [TranscriptDownloadError] = [
            .alreadyDownloading,
            .downloadFailed(statusCode: 404),
            .invalidContent,
            .conversionFailed,
            .saveFailed(URLError(.cannotCreateFile)),
        ]

        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    @Test("A failed download names the status code that caused it")
    func failureNamesTheStatusCode() throws {
        let message = try #require(
            TranscriptDownloadError.downloadFailed(statusCode: 503).errorDescription)
        #expect(message.contains("503"))
    }

    @Test("A save failure carries the underlying reason rather than swallowing it")
    func saveFailureCarriesTheCause() throws {
        let underlying = URLError(.cannotCreateFile)
        let message = try #require(
            TranscriptDownloadError.saveFailed(underlying).errorDescription)

        #expect(message.contains(underlying.localizedDescription))
    }
}
