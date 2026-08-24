//
//  TranscriptLocaleResolverTests.swift
//  PodcastAnalyzerTests
//
//  The Speech framework matches assets on a full locale identifier, so a feed
//  that says `<language>zh</language>` has to be turned into a region before
//  transcription starts. Two failures matter: producing an identifier no asset
//  matches (transcription simply never starts), and picking the wrong Chinese
//  model — zh_CN and zh_TW are different acoustic models, not a script setting,
//  so the wrong one degrades accuracy on every word rather than failing loudly.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Podcast language → Speech locale")
struct TranscriptLocaleResolverTests {

    private func locale(_ code: String) -> String {
        TranscriptLocaleResolver.locale(fromPodcastLanguage: code).identifier
    }

    @Test("A language-region pair is preserved, with the region upcased")
    func preservesExplicitRegion() {
        #expect(locale("zh-tw") == "zh_TW")
        #expect(locale("en-GB") == "en_GB")
        #expect(locale("pt-br") == "pt_BR")
    }

    @Test("A bare language gets its default region rather than staying bare")
    func fillsInDefaultRegion() {
        #expect(locale("en") == "en_US")
        #expect(locale("ja") == "ja_JP")
        #expect(locale("de") == "de_DE")
        // Portuguese podcasts are overwhelmingly Brazilian.
        #expect(locale("pt") == "pt_BR")
    }

    @Test("Bare Chinese resolves to the Mainland model, not a region-less identifier")
    func bareChineseIsMainland() {
        #expect(locale("zh") == "zh_CN")
    }

    @Test("A script subtag is mapped to the region carrying that script")
    func mapsScriptSubtagsToRegions() {
        // "zh_HANS" would be a valid-looking identifier that matches no asset.
        #expect(locale("zh-Hans") == "zh_CN")
        #expect(locale("zh-hant") == "zh_TW")
    }

    @Test("Case in the incoming code never changes the result")
    func inputCaseIsIrrelevant() {
        #expect(locale("ZH-HANT") == locale("zh-hant"))
        #expect(locale("EN") == "en_US")
    }

    @Test("A language with no default region is returned as-is instead of guessed at")
    func unknownLanguagePassesThrough() {
        // Compared against Locale's own rendering so the assertion is about the
        // resolver's choice, not Foundation's identifier normalisation.
        #expect(locale("xx") == Locale(identifier: "xx").identifier)
        #expect(locale("sw") == Locale(identifier: "sw").identifier)
        #expect(locale("sw").hasPrefix("sw"))
    }

    @Test("Odd input degrades to something Locale can hold rather than crashing")
    func handlesMalformedInput() {
        #expect(locale("") == Locale(identifier: "").identifier)
        // Three or more subtags fall through to the verbatim path.
        #expect(locale("zh-Hant-TW") == Locale(identifier: "zh-Hant-TW").identifier)
        #expect(TranscriptLocaleResolver
            .locale(fromPodcastLanguage: "zh-Hant-TW")
            .language.languageCode?.identifier == "zh")
    }
}
