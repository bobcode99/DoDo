//
//  TranscriptStoreTests.swift
//  PodcastAnalyzerTests
//
//  Verifies the SwiftData-backed transcript store that replaced the old
//  Documents/Captions/{podcastTitle}/ file tree: parse-once ingestion,
//  translation storage keyed by language, and delete/cleanup. Runs entirely
//  against a single in-memory SwiftData container shared across assertions
//  (repeatedly creating separate in-memory ModelContainers for the same
//  @Model type in one process was observed to crash the SwiftData runtime
//  on this OS build — a one-container test avoids that entirely).
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Transcript store")
struct TranscriptStoreTests {

    private static let sampleSRT = """
    1
    00:00:00,000 --> 00:00:02,000
    Hello world.

    2
    00:00:02,000 --> 00:00:04,500
    Second segment.

    """

    @Test("End-to-end: TranscriptManager-style save is findable via TranscriptSearchViewModel")
    func searchFindsGeneratedTranscript() async throws {
        let schema = Schema([EpisodeTranscriptModel.self, PodcastInfoModel.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        // TranscriptStore.shared is a process-wide singleton; point the REAL
        // singleton at this test container so production code (TranscriptStore.shared)
        // is exercised exactly as the app uses it.
        TranscriptStore.shared.setModelContainer(container)

        let entries = [
            "1\n00:00:00,000 --> 00:00:02,000\nHello world.",
            "2\n00:00:02,000 --> 00:00:04,500\nUnique searchable phrase here.",
        ]
        let srt = entries.joined(separator: "\n\n")
        try TranscriptStore.shared.saveTranscript(
            srtContent: srt, episodeTitle: "My Episode", podcastTitle: "My Show", source: "local"
        )

        let podcastInfo = PodcastInfo(
            title: "My Show",
            description: nil,
            episodes: [
                PodcastEpisodeInfo(title: "My Episode", audioURL: "https://example.com/ep.mp3")
            ],
            rssUrl: "https://example.com/feed",
            imageURL: "",
            language: "en"
        )
        let podcastModel = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date())

        let searchVM = TranscriptSearchViewModel()
        await searchVM.performSearch(query: "unique searchable", podcasts: [podcastModel])
        #expect(searchVM.results.count == 1, "results: \(searchVM.results.map(\.episode.title))")
    }

    @Test("TranscriptStore: save/load, translations, regeneration, and delete")
    func fullLifecycle() throws {
        let schema = Schema([EpisodeTranscriptModel.self, EpisodeDownloadModel.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let store = TranscriptStore()
        store.setModelContainer(container)

        // Nothing saved yet.
        #expect(!store.exists(episodeTitle: "Ep 1", podcastTitle: "Show"))

        // Save parses the SRT once; loadSegments returns the structured result.
        try store.saveTranscript(
            srtContent: Self.sampleSRT, episodeTitle: "Ep 1", podcastTitle: "Show", source: "rss"
        )
        #expect(store.exists(episodeTitle: "Ep 1", podcastTitle: "Show"))
        #expect(store.source(episodeTitle: "Ep 1", podcastTitle: "Show") == "rss")

        var segments = store.loadSegments(episodeTitle: "Ep 1", podcastTitle: "Show")
        #expect(segments?.count == 2)
        #expect(segments?.first?.text == "Hello world.")
        #expect(segments?[1].startTime == 2.0)

        // Translation round-trips, merged onto the base segments by index.
        segments![0].translatedText = "Bonjour le monde."
        segments![1].translatedText = "Deuxième segment."
        try store.saveTranslation(segments!, targetLanguage: "fr", episodeTitle: "Ep 1", podcastTitle: "Show")

        let loaded = store.loadTranslation(targetLanguage: "fr", episodeTitle: "Ep 1", podcastTitle: "Show")
        #expect(loaded?[0].translatedText == "Bonjour le monde.")
        #expect(loaded?[1].translatedText == "Deuxième segment.")
        #expect(store.availableTranslationLanguages(episodeTitle: "Ep 1", podcastTitle: "Show") == ["fr"])
        #expect(store.loadTranslation(targetLanguage: "de", episodeTitle: "Ep 1", podcastTitle: "Show") == nil)

        // Re-transcribing must clear stale translations — index alignment can't
        // survive a base transcript that was regenerated.
        try store.saveTranscript(
            srtContent: Self.sampleSRT, episodeTitle: "Ep 1", podcastTitle: "Show", source: "local"
        )
        #expect(!store.hasTranslation(targetLanguage: "fr", episodeTitle: "Ep 1", podcastTitle: "Show"))

        // Delete removes just the targeted episode; deleteAll clears everything.
        try store.saveTranscript(
            srtContent: Self.sampleSRT, episodeTitle: "Ep 2", podcastTitle: "Show B", source: "local"
        )
        try store.delete(episodeTitle: "Ep 1", podcastTitle: "Show")
        #expect(!store.exists(episodeTitle: "Ep 1", podcastTitle: "Show"))
        #expect(store.exists(episodeTitle: "Ep 2", podcastTitle: "Show B"))

        try store.deleteAll()
        #expect(!store.exists(episodeTitle: "Ep 2", podcastTitle: "Show B"))
    }
}
