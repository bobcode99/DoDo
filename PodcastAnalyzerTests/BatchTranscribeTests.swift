//
//  BatchTranscribeTests.swift
//  PodcastAnalyzerTests
//
//  Transcribing several episodes at once, and the automatic-transcription
//  rules around downloads. A Yap server transcribes from the feed URL; an
//  on-device engine needs the file, so the job waits for the download, visible
//  in the queue, and fails with the reason when the download does.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Batch transcribe")
struct BatchTranscribeTests {

    private let manager = TranscriptManager.shared
    private let downloads = DownloadManager.shared

    private func item(audioURL: String? = "https://example.invalid/episode.mp3") -> BatchTranscriptItem {
        BatchTranscriptItem(
            episode: PodcastEpisodeInfo(title: "Episode \(UUID())", audioURL: audioURL),
            podcastTitle: "Batch Test Show",
            language: "en"
        )
    }

    private func key(_ item: BatchTranscriptItem) -> String {
        EpisodeKeyUtils.makeKey(podcastTitle: item.podcastTitle, episodeTitle: item.episode.title)
    }

    private func status(_ item: BatchTranscriptItem) -> TranscriptJobStatus? {
        manager.activeJobs[key(item)]?.status
    }

    /// Marks the episode as mid-download so `queueBatch` starts no real request.
    private func pretendDownloading(_ item: BatchTranscriptItem) {
        downloads.downloadStates[key(item)] = .downloading(progress: 0.3)
    }

    private func cleanUp(_ item: BatchTranscriptItem) {
        manager.cancelJob(episodeTitle: item.episode.title, podcastTitle: item.podcastTitle)
        downloads.downloadStates.removeValue(forKey: key(item))
    }

    @Test("Yap queues the episode straight away, without downloading it")
    func yapQueuesDirectly() {
        let episode = item()
        defer { cleanUp(episode) }

        manager.queueBatch([episode], engine: .yapServer)

        #expect(status(episode) == .queued)
    }

    @Test("An on-device engine shows the episode as waiting, then queues it with the downloaded file")
    func localEngineWaitsForDownload() {
        let episode = item()
        defer { cleanUp(episode) }
        pretendDownloading(episode)

        manager.queueBatch([episode], engine: .appleSpeech)
        #expect(status(episode) == .waitingForDownload)
        #expect(manager.isGenerating(episodeTitle: episode.episode.title, podcastTitle: episode.podcastTitle))

        downloads.downloadStates[key(episode)] = .downloaded(localPath: "/tmp/batch-test.mp3")

        #expect(status(episode)?.isInFlight == true)
        #expect(status(episode) != .waitingForDownload)
        #expect(manager.activeJobs[key(episode)]?.audioPath == "/tmp/batch-test.mp3")
    }

    @Test("A failed download fails the waiting job and says why")
    func failedDownloadFailsJob() {
        // No audio URL: the download fails at once, without the network.
        let episode = item(audioURL: nil)
        defer { cleanUp(episode) }

        manager.queueBatch([episode], engine: .appleSpeech)

        guard case .failed(let reason) = status(episode) else {
            Issue.record("expected a failed job, got \(String(describing: status(episode)))")
            return
        }
        #expect(reason.contains("Invalid URL"))
    }

    @Test("A cancelled job doesn't start when its download lands later")
    func cancelledJobStaysCancelled() {
        let episode = item()
        defer { cleanUp(episode) }
        pretendDownloading(episode)
        manager.queueBatch([episode], engine: .appleSpeech)

        manager.cancelJob(episodeTitle: episode.episode.title, podcastTitle: episode.podcastTitle)
        downloads.downloadStates[key(episode)] = .downloaded(localPath: "/tmp/batch-test.mp3")

        #expect(status(episode) == nil)
    }

    @Test("Retrying a job whose audio is gone downloads it again instead of failing")
    func retryWaitsForDownloadAgain() throws {
        let episode = item(audioURL: nil)
        defer { cleanUp(episode) }
        manager.queueBatch([episode], engine: .appleSpeech)
        let failed = try #require(manager.activeJobs[key(episode)])

        pretendDownloading(episode)
        manager.retry(failed)

        #expect(status(episode) == .waitingForDownload)
    }

    @Test("Episodes already being transcribed aren't queued twice")
    func skipsInFlightEpisodes() {
        let episode = item()
        defer { cleanUp(episode) }
        pretendDownloading(episode)
        manager.queueBatch([episode], engine: .appleSpeech)

        manager.queueBatch([episode], engine: .yapServer)

        #expect(status(episode) == .waitingForDownload)
    }
}

@MainActor
@Suite("Automatic transcription backlog")
struct AutoTranscribeBacklogTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var lastWeek: Date { now.addingTimeInterval(-7 * 86_400) }

    private func download(_ show: String, _ title: String, daysAgo: Double) -> TranscriptManager.DownloadedEpisode {
        .init(
            podcastTitle: show, episodeTitle: title, localPath: "/tmp/\(title).mp3",
            downloadedDate: now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test("Only followed shows' recent downloads without a transcript are owed one")
    func followedShowsOnly() {
        let followedRecent = download("Followed", "Recent", daysAgo: 1)
        let followedTranscribed = download("Followed", "Done", daysAgo: 1)
        let followedOld = download("Followed", "Old", daysAgo: 10)
        let otherShow = download("Other", "Recent", daysAgo: 1)

        let backlog = TranscriptManager.autoTranscribeBacklog(
            [followedRecent, followedTranscribed, followedOld, otherShow],
            followedShows: ["Followed"], transcribeAllDownloads: false,
            transcribed: [EpisodeKeyUtils.makeKey(podcastTitle: "Followed", episodeTitle: "Done")],
            since: lastWeek)

        #expect(backlog == [followedRecent])
    }

    @Test("\"Transcribe Downloads\" covers every show's recent downloads")
    func transcribeAllDownloads() {
        let otherShow = download("Other", "Recent", daysAgo: 1)
        let old = download("Other", "Old", daysAgo: 8)

        let backlog = TranscriptManager.autoTranscribeBacklog(
            [otherShow, old], followedShows: [], transcribeAllDownloads: true,
            transcribed: [], since: lastWeek)

        #expect(backlog == [otherShow])
    }
}

@MainActor
@Suite("Automatic transcription engine")
struct AutoTranscribeEngineTests {

    private let manager = TranscriptManager.shared

    private func withSelectedEngine(_ engine: TranscriptEngine, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: "transcriptEngine")
        let savedConsent = manager.allowLocalOnBattery
        defaults.set(engine.rawValue, forKey: "transcriptEngine")
        manager.setAllowLocalOnBattery(true)
        defer {
            defaults.set(saved, forKey: "transcriptEngine")
            manager.setAllowLocalOnBattery(savedConsent)
        }
        body()
    }

    @Test(
        "An on-device engine is used even though a Yap URL is always saved",
        arguments: [TranscriptEngine.appleSpeech, .whisper]
    )
    func selectedLocalEngineWins(engine: TranscriptEngine) {
        #expect(!YapServerSettings.shared.serverURL.isEmpty)
        withSelectedEngine(engine) {
            guard case .local(let resolved) = manager.resolveAutoTranscribeEngine() else {
                Issue.record("expected the selected on-device engine")
                return
            }
            #expect(resolved == engine)
        }
    }

    private func newEpisodeJob(selected engine: TranscriptEngine) async -> TranscriptJob? {
        let episode = PodcastEpisodeInfo(
            title: "New \(UUID())", audioURL: "https://example.invalid/new.mp3")
        let show = "Followed Test Show"
        defer { manager.cancelJob(episodeTitle: episode.title, podcastTitle: show) }

        // The engine is read synchronously, so other suites never see this value.
        withSelectedEngine(engine) {
            manager.autoTranscribeNewEpisodes([episode], podcastTitle: show, language: "zh-Hant")
        }

        let key = EpisodeKeyUtils.makeKey(podcastTitle: show, episodeTitle: episode.title)
        for _ in 0..<20 {
            if let job = manager.activeJobs[key] { return job }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return nil
    }

    @Test("With Apple Speech selected, a new episode never becomes a Yap job")
    func newEpisodeStaysOffYap() async {
        #expect(await newEpisodeJob(selected: .appleSpeech) == nil)
    }

    @Test("With Yap selected, a new episode is transcribed from its feed URL")
    func newEpisodeUsesYap() async {
        let job = await newEpisodeJob(selected: .yapServer)
        #expect(job?.engine == .yapServer)
        #expect(job?.audioRemoteURL == "https://example.invalid/new.mp3")
    }

    @Test("Yap runs when it's the selected engine")
    func selectedYapWins() {
        withSelectedEngine(.yapServer) {
            guard case .yap = manager.resolveAutoTranscribeEngine() else {
                Issue.record("expected Yap")
                return
            }
        }
    }
}
