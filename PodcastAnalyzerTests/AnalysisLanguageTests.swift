//
//  AnalysisLanguageTests.swift
//  PodcastAnalyzerTests
//
//  The prompt used to name the device language by language code alone, so a
//  zh-Hant-TW device asked for "中文" and got Simplified Chinese back.
//

import Testing

@testable import PodcastAnalyzer

@Suite("AI response language")
struct AnalysisLanguageTests {

    @Test("Chinese keeps its script, so models don't default to Simplified",
          arguments: zip(["zh-Hant-TW", "zh-Hans-CN"], ["Traditional", "Simplified"]))
    func keepsScript(_ identifier: String, _ script: String) {
        #expect(AnalysisLanguage.promptLanguageName(for: identifier).contains(script))
    }

    @Test("Names are English, whatever the device language is")
    func englishNames() {
        #expect(AnalysisLanguage.promptLanguageName(for: "ja-JP") == "Japanese (Japan)")
    }
}
