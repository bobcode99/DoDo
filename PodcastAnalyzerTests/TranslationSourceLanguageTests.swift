//
//  TranslationSourceLanguageTests.swift
//  PodcastAnalyzerTests
//
//  The transcript's own language comes from its text, not the feed's
//  <language> tag, and is never offered as a translation target: picking
//  Traditional Chinese for a Traditional Chinese show translates nothing.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Translation source language")
struct TranslationSourceLanguageTests {

    private func isLanguage(_ language: Locale.Language?, _ identifier: String) -> Bool {
        language?.isEquivalent(to: Locale.Language(identifier: identifier)) ?? false
    }

    @Test("Traditional Chinese transcript text is detected as zh-Hant")
    func detectsTraditionalChinese() {
        let detected = TranscriptLanguageDetector.dominantLanguage(of: [
            "今天我們來聊聊臺灣的咖啡文化，還有這幾年獨立咖啡店越來越多的現象。",
            "很多年輕人選擇回到家鄉開店，讓這個產業變得更加豐富。",
        ])
        #expect(isLanguage(detected, "zh-Hant"))
        #expect(!isLanguage(detected, "zh-Hans"))
    }

    @Test("Simplified Chinese transcript text is detected as zh-Hans")
    func detectsSimplifiedChinese() {
        let detected = TranscriptLanguageDetector.dominantLanguage(of: [
            "今天我们来聊聊中国的咖啡文化，还有这几年独立咖啡店越来越多的现象。",
            "很多年轻人选择回到家乡开店，让这个产业变得更加丰富。",
        ])
        #expect(isLanguage(detected, "zh-Hans"))
        #expect(!isLanguage(detected, "zh-Hant"))
    }

    @Test("English transcript text is detected as en")
    func detectsEnglish() {
        let detected = TranscriptLanguageDetector.dominantLanguage(of: [
            "Today we're talking about coffee culture,",
            "and why independent coffee shops keep opening across the country.",
        ])
        #expect(isLanguage(detected, "en"))
    }

    @Test("An empty transcript has no detectable language")
    func emptyIsUndetermined() {
        #expect(TranscriptLanguageDetector.dominantLanguage(of: []) == nil)
        #expect(TranscriptLanguageDetector.dominantLanguage(of: ["", " "]) == nil)
    }

    @Test("Translating into the transcript's own language counts as the same language")
    func sameLanguageRule() throws {
        #expect(TranslationTargetLanguage.english.isSameLanguage(as: Locale.Language(identifier: "en-US")))
        #expect(!TranslationTargetLanguage.traditionalChinese.isSameLanguage(as: Locale.Language(identifier: "zh-Hans")))
        #expect(!TranslationTargetLanguage.english.isSameLanguage(as: nil))
        let device = try #require(Locale.preferredLanguages.first)
        #expect(TranslationTargetLanguage.deviceLanguage.isSameLanguage(as: Locale.Language(identifier: device)))
    }

    @Test(
        "Region doesn't make a different language",
        arguments: ["en-TW", "en-GB", "en-HK"]
    )
    func regionIsIgnored(deviceLanguage: String) {
        // An English device set to a non-US region reports e.g. "en-TW", while
        // the transcript is detected as plain "en".
        let device = Locale.Language(identifier: deviceLanguage)
        #expect(TranslationTargetLanguage.english.isSameLanguage(as: device))
        let offered = TranslationLanguagePickerSheet.offeredLanguages(source: device)
        #expect(!offered.contains(.english))
    }

    @Test("Script still separates Traditional from Simplified Chinese")
    func scriptStillMatters() {
        #expect(TranslationTargetLanguage.traditionalChinese.isSameLanguage(as: Locale.Language(identifier: "zh-TW")))
        #expect(!TranslationTargetLanguage.simplifiedChinese.isSameLanguage(as: Locale.Language(identifier: "zh-TW")))
    }

    @Test("Before the transcript loads, a Traditional Chinese show reads as Traditional even when the feed says zh")
    func traditionalShowWithoutTranscript() {
        let episode = PodcastEpisodeInfo(
            title: "EP178【女人心事】荒野攝影師徐仁修 重返差點死掉的巴布亞",
            podcastEpisodeDescription: "<p>這一集我們邀請到荒野攝影師徐仁修，聊聊他重返巴布亞紐幾內亞的旅程，以及這些年來對自然與攝影的體會。</p>"
        )
        let coordinator = TranslationCoordinator(episode: episode, podcastTitle: "女人心事", podcastLanguage: "zh")

        let source = coordinator.sourceLanguage
        #expect(TranslationTargetLanguage.traditionalChinese.isSameLanguage(as: source))
        #expect(!TranslationLanguagePickerSheet.offeredLanguages(source: source).contains(.traditionalChinese))
        #expect(TranslationLanguagePickerSheet.offeredLanguages(source: source).contains(.simplifiedChinese))
    }

    @Test("The picker hides only the transcript's own language")
    func pickerHidesSourceLanguage() {
        let offered = TranslationLanguagePickerSheet.offeredLanguages(source: Locale.Language(identifier: "zh-Hant"))
        let hidden = Set(TranslationTargetLanguage.allCases).subtracting(offered)
        #expect(hidden == [.deviceLanguage, .traditionalChinese])
    }

    @Test("With no known source language the picker offers every explicit language")
    func pickerWithoutSourceHidesNothing() {
        let offered = TranslationLanguagePickerSheet.offeredLanguages(source: nil)
        let hidden = Set(TranslationTargetLanguage.allCases).subtracting(offered)
        #expect(hidden == [.deviceLanguage])
    }
}
