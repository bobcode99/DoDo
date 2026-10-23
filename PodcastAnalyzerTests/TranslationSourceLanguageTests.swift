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
