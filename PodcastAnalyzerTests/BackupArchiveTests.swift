//
//  BackupArchiveTests.swift
//  PodcastAnalyzerTests
//
//  `backup.json` leaves the device — AirDrop, Files, iCloud Drive, a support
//  email. Two properties matter and neither is visible by inspection:
//
//  1. The settings safelist must never let a credential out. It is an allow-list
//     with a substring deny-list behind it, and the deny-list is the layer that
//     saves you when somebody adds "openaiApiKey" to the allow-list by habit.
//  2. `BackupSettingValue` has to keep Bool and Int apart. `UserDefaults` hands
//     both back as `NSNumber`, so a Bool restored as `1` turns a toggle into an
//     integer that no `@AppStorage(Bool)` read can ever see.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Backup archive")
struct BackupArchiveTests {

    // MARK: - Settings safelist

    @Test("Every safelisted key is actually allowed")
    func safelistedKeysAreAllowed() {
        // A loop rather than `@Test(arguments: BackupSettingsSafelist.keys)`: the
        // `arguments:` expression is evaluated in a nonisolated context, and the
        // safelist is MainActor-isolated like everything else in the app target.
        for key in BackupSettingsSafelist.keys {
            #expect(BackupSettingsSafelist.isAllowed(key), "\(key) should be allowed")
        }
    }

    @Test("A key nobody safelisted is refused")
    func unlistedKeysAreRefused() {
        #expect(BackupSettingsSafelist.isAllowed("someRandomKey") == false)
        #expect(BackupSettingsSafelist.isAllowed("") == false)
    }

    @Test("Anything that looks like a credential is refused whatever its casing",
          arguments: [
            "openaiApiKey", "OPENAI_API_KEY", "anthropic_api_key",
            "authToken", "refreshToken", "clientSecret", "oauthState",
            "userPassword", "storedCredential",
          ])
    func credentialsAreRefused(_ key: String) {
        #expect(BackupSettingsSafelist.isAllowed(key) == false, "\(key) must not be exported")
    }

    @Test("The deny-list outranks the safelist, so a credential added by mistake still can't escape")
    func denyListBeatsSafelist() {
        // Simulates the realistic accident: a key that is on the allow-list and
        // also names a secret.
        let planted = BackupSettingsSafelist.keys.first! + "ApiKey"
        #expect(BackupSettingsSafelist.isAllowed(planted) == false)
    }

    @Test("Key matching is exact, not prefix-based")
    func matchingIsExact() {
        let real = "defaultPlaybackSpeed"
        #expect(BackupSettingsSafelist.isAllowed(real))
        #expect(BackupSettingsSafelist.isAllowed(real + "Extra") == false)
        #expect(BackupSettingsSafelist.isAllowed(real.lowercased()) == false)
    }

    @Test("The safelist has no duplicates")
    func safelistIsDistinct() {
        #expect(Set(BackupSettingsSafelist.keys).count == BackupSettingsSafelist.keys.count)
    }

    // MARK: - Setting values

    @Test("A Bool from UserDefaults is lifted as a Bool, not as 0 or 1")
    func liftsBooleansAsBooleans() {
        #expect(BackupSettingValue.from(true) == .bool(true))
        #expect(BackupSettingValue.from(false) == .bool(false))
    }

    @Test("Integers, doubles, floats and strings each keep their type")
    func liftsOtherScalars() {
        #expect(BackupSettingValue.from(42) == .int(42))
        #expect(BackupSettingValue.from(1.5) == .double(1.5))
        #expect(BackupSettingValue.from(Float(2.5)) == .double(2.5))
        #expect(BackupSettingValue.from("zh-Hant") == .string("zh-Hant"))
    }

    @Test("Types the archive can't represent are dropped rather than mangled")
    func refusesUnsupportedTypes() {
        #expect(BackupSettingValue.from([1, 2, 3]) == nil)
        #expect(BackupSettingValue.from(["a": 1]) == nil)
        #expect(BackupSettingValue.from(Date()) == nil)
        #expect(BackupSettingValue.from(Data()) == nil)
    }

    @Test("A value survives JSON encoding with its type intact",
          arguments: [BackupSettingValue.bool(true), .bool(false), .int(0), .int(-7),
                      .double(1.25), .string("hello")])
    func valuesRoundTripThroughJSON(_ value: BackupSettingValue) throws {
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(BackupSettingValue.self, from: data) == value)
    }

    @Test("A JSON payload of an unsupported shape fails to decode instead of decoding as junk")
    func rejectsUnsupportedJSON() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(BackupSettingValue.self, from: Data("[1,2]".utf8))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(BackupSettingValue.self, from: Data("null".utf8))
        }
    }

    @Test("Writing a value back into defaults preserves the type it was captured with")
    func writesBackWithTheRightType() throws {
        let suiteName = "BackupArchiveTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        BackupSettingValue.bool(true).write(to: defaults, key: "flag")
        BackupSettingValue.int(3).write(to: defaults, key: "count")
        BackupSettingValue.double(1.25).write(to: defaults, key: "speed")
        BackupSettingValue.string("en").write(to: defaults, key: "language")

        #expect(defaults.bool(forKey: "flag"))
        #expect(defaults.integer(forKey: "count") == 3)
        #expect(defaults.double(forKey: "speed") == 1.25)
        #expect(defaults.string(forKey: "language") == "en")

        // The captured Bool must come back as a Bool, not as the integer 1.
        let relifted = try #require(defaults.object(forKey: "flag").flatMap(BackupSettingValue.from))
        #expect(relifted == .bool(true))
    }

    @Test("A defaults value survives capture, encode, decode and restore")
    func settingsRoundTripThroughDefaults() throws {
        let sourceName = "BackupArchiveTests.source.\(UUID().uuidString)"
        let targetName = "BackupArchiveTests.target.\(UUID().uuidString)"
        let source = try #require(UserDefaults(suiteName: sourceName))
        let target = try #require(UserDefaults(suiteName: targetName))
        defer {
            source.removePersistentDomain(forName: sourceName)
            target.removePersistentDomain(forName: targetName)
        }

        source.set(1.5, forKey: "defaultPlaybackSpeed")
        source.set(true, forKey: "autoPlayNextEpisode")
        source.set("zh-Hant", forKey: "appLanguage")
        source.set("sk-should-never-travel", forKey: "openaiApiKey")

        var captured: [String: BackupSettingValue] = [:]
        for key in source.dictionaryRepresentation().keys where BackupSettingsSafelist.isAllowed(key) {
            if let raw = source.object(forKey: key), let value = BackupSettingValue.from(raw) {
                captured[key] = value
            }
        }

        let settings = BackupSettings(values: captured)
        let decoded = try JSONDecoder().decode(
            BackupSettings.self, from: try JSONEncoder().encode(settings))

        #expect(decoded.values["defaultPlaybackSpeed"] == .double(1.5))
        #expect(decoded.values["autoPlayNextEpisode"] == .bool(true))
        #expect(decoded.values["appLanguage"] == .string("zh-Hant"))
        #expect(decoded.values["openaiApiKey"] == nil)

        for (key, value) in decoded.values {
            value.write(to: target, key: key)
        }
        #expect(target.double(forKey: "defaultPlaybackSpeed") == 1.5)
        #expect(target.bool(forKey: "autoPlayNextEpisode"))
        #expect(target.object(forKey: "openaiApiKey") == nil)
    }

    // MARK: - Archive envelope

    @Test("A whole archive survives a JSON round trip with its rows intact")
    func archiveRoundTrips() throws {
        let archive = BackupArchive(
            exportedAt: Date(timeIntervalSince1970: 1_770_000_000),
            appVersion: "1.2.3",
            build: "42",
            podcasts: [
                BackupPodcast(
                    rssUrl: "https://example.com/feed.xml", title: "The Show",
                    imageURL: "https://example.com/art.jpg", language: "en",
                    podcastDescription: "A show.", dateAdded: Date(timeIntervalSince1970: 0),
                    isSubscribed: true, autoTranscribeNewEpisodes: false,
                    autoDownloadSetting: "off", episodeFilterInclude: "",
                    episodeFilterExclude: "bonus", episodeFilterMinDuration: 300,
                    detectedCadence: "weekly")
            ],
            episodes: [
                BackupEpisode(
                    podcastTitle: "The Show", episodeTitle: "Episode 1",
                    audioURL: "https://example.com/1.mp3", imageURL: nil,
                    pubDate: Date(timeIntervalSince1970: 1_700_000_000), duration: 3600,
                    lastPlaybackPosition: 120, isCompleted: false, lastPlayedDate: nil,
                    playCount: 1, isStarred: true, notes: nil, upNextDismissedAt: nil,
                    autoDownloadEnabled: false)
            ],
            queue: [],
            aiAnalyses: [],
            settings: BackupSettings(values: ["defaultPlaybackSpeed": .double(1.5)])
        )

        let decoded = try JSONDecoder().decode(
            BackupArchive.self, from: try JSONEncoder().encode(archive))

        #expect(decoded.version == BackupArchive.currentVersion)
        #expect(decoded.podcasts.count == 1)
        #expect(decoded.podcasts[0].episodeFilterExclude == "bonus")
        #expect(decoded.episodes[0].lastPlaybackPosition == 120)
        #expect(decoded.episodes[0].isStarred)
        #expect(decoded.settings.values["defaultPlaybackSpeed"] == .double(1.5))
        #expect(decoded.aiFormatHints.isEmpty)
    }

    @Test("An archive from a device with nothing in it decodes to an empty library")
    func decodesEmptyArchive() throws {
        let json = """
        {
          "version": 1,
          "exportedAt": 0,
          "appVersion": "1.0.0",
          "build": "1",
          "podcasts": [],
          "episodes": [],
          "queue": [],
          "aiAnalyses": [],
          "settings": { "values": {} },
          "aiFormatHints": {}
        }
        """

        let decoded = try JSONDecoder().decode(BackupArchive.self, from: Data(json.utf8))
        #expect(decoded.podcasts.isEmpty)
        #expect(decoded.aiFormatHints.isEmpty)
    }

    @Test("Every section is required — a file missing one is rejected, not restored half-way")
    func everySectionIsRequired() {
        // Swift's synthesized decoding does not fall back to the property
        // defaults, so an archive written by an older schema is refused outright
        // rather than restoring a partial library. That matches the project's
        // "no backward compatibility" rule; this test exists so the behaviour is
        // a decision on record rather than a surprise during a restore.
        let missingHints = """
        {
          "version": 1, "exportedAt": 0, "appVersion": "1.0.0", "build": "1",
          "podcasts": [], "episodes": [], "queue": [], "aiAnalyses": [],
          "settings": { "values": {} }
        }
        """

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(BackupArchive.self, from: Data(missingHints.utf8))
        }
    }

    @Test("Truncated or foreign JSON is rejected rather than restored partially")
    func rejectsCorruptArchive() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(BackupArchive.self, from: Data("{".utf8))
        }
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(BackupArchive.self, from: Data(#"{"version":1}"#.utf8))
        }
    }
}
