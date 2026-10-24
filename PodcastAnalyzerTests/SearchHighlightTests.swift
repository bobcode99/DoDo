//
//  SearchHighlightTests.swift
//  PodcastAnalyzerTests
//
//  The transcript search highlights the same text `localizedStandardContains`
//  matched, without ever indexing into a different string than it slices.
//

import Foundation
import SwiftUI
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Search highlight")
struct SearchHighlightTests {

    private func highlightedParts(_ text: String, _ query: String) -> [String] {
        let attributed = SearchHighlightedText.highlighted(text, matching: query)
        return attributed.runs
            .filter { $0.backgroundColor != nil }
            .map { String(attributed[$0.range].characters) }
    }

    @Test("Text after a character whose lowercase form is longer keeps the right range")
    func lowercasingDoesNotShiftRanges() {
        #expect(highlightedParts("İstanbul", "bul") == ["bul"])
    }

    @Test("Matching ignores case")
    func ignoresCase() {
        #expect(highlightedParts("Hello there, hello", "HELLO") == ["Hello", "hello"])
    }

    @Test("Matching ignores diacritics, like the search itself")
    func ignoresDiacritics() {
        #expect("Café au lait".localizedStandardContains("cafe"))
        #expect(highlightedParts("Café au lait", "cafe") == ["Café"])
    }

    @Test("Surrounding spaces in the query are ignored")
    func trimsQuery() {
        #expect(highlightedParts("foo bar", "foo ") == ["foo"])
    }

    @Test("Highlighting never changes the characters")
    func preservesText() {
        let text = "İstanbul'da bir gün"
        let attributed = SearchHighlightedText.highlighted(text, matching: "bir")
        #expect(String(attributed.characters) == text)
    }

    @Test("No match or empty query highlights nothing")
    func noMatch() {
        #expect(highlightedParts("Hello", "xyz").isEmpty)
        #expect(highlightedParts("Hello", "   ").isEmpty)
    }
}
