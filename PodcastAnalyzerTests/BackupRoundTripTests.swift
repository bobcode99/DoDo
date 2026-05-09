//
//  BackupRoundTripTests.swift
//  PodcastAnalyzerTests
//
//  Validates that the backup.json schema round-trips and that the safelist
//  rejects sensitive UserDefaults keys.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@Suite("Backup round-trip")
@MainActor
struct BackupRoundTripTests {

    // MARK: - Helpers

    private func makeArchive() -> BackupArchive {
        let podcast = BackupPodcast(
            rssUrl: "https://example.com/feed.xml",
            title: "Test Show",
            imageURL: "https://example.com/art.jpg",
            language: "en",
            podcastDescription: "A show",
            dateAdded: Date(timeIntervalSince1970: 1_700_000_000),
            isSubscribed: true,
            autoTranscribeWithYap: false,
            autoDownloadSetting: "inheritGlobal",
            episodeFilterInclude: "tech",
            episodeFilterExclude: "ads",
            episodeFilterMinDuration: 600,
            detectedCadence: "weekly"
        )

        let starredHalfPlayed = BackupEpisode(
            podcastTitle: "Test Show",
            episodeTitle: "Ep 1",
            audioURL: "https://example.com/ep1.mp3",
            imageURL: "https://example.com/ep1.jpg",
            pubDate: Date(timeIntervalSince1970: 1_700_100_000),
            duration: 3600,
            lastPlaybackPosition: 1234.5,
            isCompleted: false,
            lastPlayedDate: Date(timeIntervalSince1970: 1_700_200_000),
            playCount: 1,
            isStarred: true,
            notes: nil,
            upNextDismissedAt: nil,
            transcriptSource: "rss",
            autoDownloadEnabled: true
        )

        let completed = BackupEpisode(
            podcastTitle: "Test Show",
            episodeTitle: "Ep 2",
            audioURL: "https://example.com/ep2.mp3",
            imageURL: nil,
            pubDate: nil,
            duration: 1800,
            lastPlaybackPosition: 1800,
            isCompleted: true,
            lastPlayedDate: Date(timeIntervalSince1970: 1_700_300_000),
            playCount: 2,
            isStarred: false,
            notes: "great episode",
            upNextDismissedAt: Date(timeIntervalSince1970: 1_700_400_000),
            transcriptSource: "local",
            autoDownloadEnabled: false
        )

        let queue = (0..<4).map { idx in
            BackupQueueItem(
                position: idx,
                id: "Test Show\u{1F}Queued \(idx)",
                episodeTitle: "Queued \(idx)",
                podcastTitle: "Test Show",
                audioURL: "https://example.com/q\(idx).mp3",
                imageURL: "https://example.com/q\(idx).jpg",
                episodeDescription: "desc \(idx)",
                pubDate: Date(timeIntervalSince1970: 1_700_500_000 + Double(idx)),
                duration: 1200,
                guid: "guid-\(idx)"
            )
        }

        let analysis = BackupAIAnalysis(
            episodeAudioURL: "https://example.com/ep1.mp3",
            episodeTitle: "Ep 1",
            podcastTitle: "Test Show",
            analysisJSON: #"{"overview":"hi"}"#,
            qaHistoryJSON: "[]",
            provider: "gemini",
            model: "gemini-2.0",
            generatedAt: Date(timeIntervalSince1970: 1_700_600_000),
            createdAt: Date(timeIntervalSince1970: 1_700_600_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_600_500)
        )

        let quickTags = BackupQuickTags(
            episodeAudioURL: "https://example.com/ep1.mp3",
            episodeTitle: "Ep 1",
            tags: ["news", "politics"],
            primaryCategory: "News",
            secondaryCategory: "World",
            contentType: "interview",
            difficulty: "intermediate",
            briefSummary: "summary",
            generatedAt: Date(timeIntervalSince1970: 1_700_700_000)
        )

        let settings = BackupSettings(values: [
            "defaultPlaybackSpeed": .double(1.25),
            "skipForwardInterval": .int(30),
            "autoPlayNextEpisode": .bool(true),
            "selectedTranscriptLocale": .string("en-US"),
        ])

        return BackupArchive(
            version: BackupArchive.currentVersion,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "1.0.0",
            build: "42",
            podcasts: [podcast],
            episodes: [starredHalfPlayed, completed],
            queue: queue,
            aiAnalyses: [analysis],
            quickTags: [quickTags],
            settings: settings
        )
    }

    private func encode(_ archive: BackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    private func decode(_ data: Data) throws -> BackupArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupArchive.self, from: data)
    }

    // MARK: - Tests

    @Test func archive_encodeDecode_preservesEverything() throws {
        let original = makeArchive()
        let data = try encode(original)
        let decoded = try decode(data)

        #expect(decoded.version == original.version)
        #expect(decoded.appVersion == original.appVersion)
        #expect(decoded.build == original.build)
        #expect(decoded.podcasts.count == 1)
        #expect(decoded.podcasts[0].rssUrl == "https://example.com/feed.xml")
        #expect(decoded.podcasts[0].episodeFilterInclude == "tech")
        #expect(decoded.podcasts[0].episodeFilterMinDuration == 600)
        #expect(decoded.podcasts[0].detectedCadence == "weekly")

        #expect(decoded.episodes.count == 2)
        let ep1 = decoded.episodes[0]
        #expect(ep1.episodeTitle == "Ep 1")
        #expect(ep1.lastPlaybackPosition == 1234.5)
        #expect(ep1.isStarred)
        #expect(!ep1.isCompleted)
        #expect(ep1.notes == nil)
        let ep2 = decoded.episodes[1]
        #expect(ep2.isCompleted)
        #expect(ep2.notes == "great episode")
        #expect(ep2.autoDownloadEnabled == false)
        #expect(ep2.upNextDismissedAt != nil)

        #expect(decoded.queue.count == 4)
        #expect(decoded.queue.map(\.position) == [0, 1, 2, 3])
        #expect(decoded.queue[2].guid == "guid-2")

        #expect(decoded.aiAnalyses.count == 1)
        #expect(decoded.aiAnalyses[0].provider == "gemini")
        #expect(decoded.aiAnalyses[0].analysisJSON == #"{"overview":"hi"}"#)

        #expect(decoded.quickTags.count == 1)
        #expect(decoded.quickTags[0].tags == ["news", "politics"])

        #expect(decoded.settings.values["defaultPlaybackSpeed"] == .double(1.25))
        #expect(decoded.settings.values["skipForwardInterval"] == .int(30))
        #expect(decoded.settings.values["autoPlayNextEpisode"] == .bool(true))
        #expect(decoded.settings.values["selectedTranscriptLocale"] == .string("en-US"))
    }

    @Test func archive_decodeIsIdempotent() throws {
        let original = makeArchive()
        let firstPass = try decode(try encode(original))
        let secondPass = try decode(try encode(firstPass))
        // Compare via re-encoded canonical form rather than implementing Equatable.
        let firstData = try encode(firstPass)
        let secondData = try encode(secondPass)
        #expect(firstData == secondData)
    }

    // MARK: - Safelist

    @Test func safelist_acceptsKnownKeys() {
        #expect(BackupSettingsSafelist.isAllowed("defaultPlaybackSpeed"))
        #expect(BackupSettingsSafelist.isAllowed("skipForwardInterval"))
        #expect(BackupSettingsSafelist.isAllowed("appLanguage"))
    }

    @Test func safelist_rejectsUnknownKeys() {
        #expect(!BackupSettingsSafelist.isAllowed("randomThing"))
        #expect(!BackupSettingsSafelist.isAllowed(""))
    }

    @Test func safelist_rejectsSensitiveSubstrings() {
        // Even if these were ever added to the safelist by mistake, the deny list
        // is the second layer of defense.
        #expect(!BackupSettingsSafelist.isAllowed("openaiApiKey"))
        #expect(!BackupSettingsSafelist.isAllowed("OPENAI_API_KEY"))
        #expect(!BackupSettingsSafelist.isAllowed("googleAccessToken"))
        #expect(!BackupSettingsSafelist.isAllowed("clientSecret"))
        #expect(!BackupSettingsSafelist.isAllowed("oauthRefresh"))
        #expect(!BackupSettingsSafelist.isAllowed("userPassword"))
    }

    // MARK: - BackupSettingValue type lifting

    @Test func settingValue_liftsBoolFromNSNumber() {
        let raw: Any = NSNumber(value: true)
        #expect(BackupSettingValue.from(raw) == .bool(true))
    }

    @Test func settingValue_liftsIntFromNSNumber() {
        let raw: Any = NSNumber(value: 42)
        #expect(BackupSettingValue.from(raw) == .int(42))
    }

    @Test func settingValue_liftsDoubleFromNSNumber() {
        let raw: Any = NSNumber(value: 1.5)
        #expect(BackupSettingValue.from(raw) == .double(1.5))
    }

    @Test func settingValue_liftsString() {
        #expect(BackupSettingValue.from("hello") == .string("hello"))
    }

    @Test func settingValue_rejectsUnsupportedType() {
        let raw: Any = ["a", "b"]
        #expect(BackupSettingValue.from(raw) == nil)
    }
}
