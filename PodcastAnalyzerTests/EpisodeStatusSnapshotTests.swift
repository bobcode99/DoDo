//
//  EpisodeStatusSnapshotTests.swift
//  PodcastAnalyzerTests
//
//  Guards the batched status fetches that replaced per-row lookups in
//  `EpisodeListViewModel.refreshStatusSnapshots()`.
//
//  The transcript half filters on `episodeId.starts(with:)`. That compiles for
//  any predicate, but SwiftData decides at *fetch* time whether it can translate
//  an operation to the store — and the call site swallows the throw so the badge
//  simply disappears. A silent "no episode has a transcript" is exactly the kind
//  of regression nothing else would catch, hence this test.
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Batched episode status snapshots")
struct EpisodeStatusSnapshotTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([EpisodeTranscriptModel.self, EpisodeAIAnalysis.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func key(_ podcast: String, _ episode: String) -> String {
        EpisodeKeyUtils.makeKey(podcastTitle: podcast, episodeTitle: episode)
    }

    @Test("prefix predicate scopes transcripts to one podcast")
    func transcriptPrefixPredicateIsSupported() throws {
        let container = try makeContainer()
        let context = container.mainContext

        for (podcast, episode) in [
            ("Daily Tech", "Episode 1"),
            ("Daily Tech", "Episode 2"),
            ("Other Show", "Episode 1"),
        ] {
            context.insert(EpisodeTranscriptModel(episodeId: key(podcast, episode)))
        }
        try context.save()

        let prefix = "Daily Tech" + EpisodeKeyUtils.delimiter
        let descriptor = FetchDescriptor<EpisodeTranscriptModel>(
            predicate: #Predicate { $0.episodeId.starts(with: prefix) }
        )

        // Throwing here is the failure we care about: the production call site
        // catches and logs, which would leave every transcript badge blank.
        let matches = try context.fetch(descriptor)

        #expect(Set(matches.map(\.episodeId)) == [
            key("Daily Tech", "Episode 1"),
            key("Daily Tech", "Episode 2"),
        ], "must match this podcast's rows and exclude the other show's")
    }

    @Test("a podcast with no transcripts yields an empty set, not a throw")
    func emptyPrefixMatchIsEmpty() throws {
        let container = try makeContainer()
        let context = container.mainContext

        context.insert(EpisodeTranscriptModel(episodeId: key("Other Show", "Episode 1")))
        try context.save()

        let prefix = "Daily Tech" + EpisodeKeyUtils.delimiter
        let descriptor = FetchDescriptor<EpisodeTranscriptModel>(
            predicate: #Predicate { $0.episodeId.starts(with: prefix) }
        )
        #expect(try context.fetch(descriptor).isEmpty)
    }

    @Test("titles sharing a prefix don't bleed across the delimiter")
    func delimiterPreventsPrefixCollision() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // "Daily" is a prefix of "Daily Tech" — the U+001F delimiter is what
        // keeps the shorter title from matching the longer one's rows.
        for (podcast, episode) in [("Daily", "Episode 1"), ("Daily Tech", "Episode 1")] {
            context.insert(EpisodeTranscriptModel(episodeId: key(podcast, episode)))
        }
        try context.save()

        let prefix = "Daily" + EpisodeKeyUtils.delimiter
        let descriptor = FetchDescriptor<EpisodeTranscriptModel>(
            predicate: #Predicate { $0.episodeId.starts(with: prefix) }
        )
        let matches = try context.fetch(descriptor)
        #expect(matches.map(\.episodeId) == [key("Daily", "Episode 1")])
    }

    @Test("AI-analysis rows are scoped by podcast title")
    func analysisFetchScopesByPodcast() throws {
        let container = try makeContainer()
        let context = container.mainContext

        for (podcast, url) in [
            ("Daily Tech", "https://a.example/1.mp3"),
            ("Other Show", "https://b.example/1.mp3"),
        ] {
            let analysis = EpisodeAIAnalysis(
                episodeAudioURL: url,
                episodeTitle: "Episode 1",
                podcastTitle: podcast
            )
            analysis.analysisJSON = "{}"
            context.insert(analysis)
        }
        try context.save()

        let title = "Daily Tech"
        let descriptor = FetchDescriptor<EpisodeAIAnalysis>(
            predicate: #Predicate { $0.podcastTitle == title }
        )
        let matches = try context.fetch(descriptor)
        #expect(matches.map(\.episodeAudioURL) == ["https://a.example/1.mp3"])
    }
}
