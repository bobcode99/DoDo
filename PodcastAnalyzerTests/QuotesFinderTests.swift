//
//  QuotesFinderTests.swift
//  PodcastAnalyzerTests
//
//  The model returns notable quotes without timestamps (sending it a timestamped
//  transcript would multiply the prompt cost), so the app locates each quote in
//  the transcript itself. Two ways to be wrong: no timestamp, which costs the
//  user a tap-to-seek; and a *confidently wrong* timestamp, which seeks to the
//  wrong part of the episode. The two-token floor on the fuzzy path is what
//  keeps the second from happening, so it is pinned here.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Quote timestamp matching")
struct QuotesFinderTests {

    private let segments = [
        QuotesFinder.Segment(
            startTime: 0,
            text: "Welcome to the show, today we are talking about distributed systems."),
        QuotesFinder.Segment(
            startTime: 65,
            text: "The hardest problem in computing is cache invalidation and naming things."),
        QuotesFinder.Segment(
            startTime: 3_725,
            text: "That is all we have time for, thanks for listening everyone."),
    ]

    private func enrich(_ text: String, timestamp: String? = nil) -> TimestampedQuote {
        QuotesFinder.enrich(
            quotes: [TimestampedQuote(text: text, timestamp: timestamp)],
            segments: segments
        )[0]
    }

    // MARK: - Exact matches

    @Test("A quote lifted verbatim gets the start time of the segment it came from")
    func matchesVerbatimQuote() {
        #expect(enrich("The hardest problem in computing is cache invalidation").timestamp == "1:05")
    }

    @Test("Case and punctuation differences don't block a match")
    func matchIgnoresCaseAndPunctuation() {
        #expect(enrich("the HARDEST problem, in computing: is cache invalidation!").timestamp
                == "1:05")
    }

    @Test("A short quote is matched whole rather than by a prefix")
    func matchesShortQuote() {
        #expect(enrich("cache invalidation").timestamp == "1:05")
    }

    @Test("Timestamps past an hour gain an hours field")
    func formatsLongTimestamps() {
        #expect(enrich("thanks for listening everyone").timestamp == "1:02:05")
    }

    @Test("A quote from the opening segment is timed at zero, not dropped")
    func matchesOpeningSegment() {
        #expect(enrich("talking about distributed systems").timestamp == "0:00")
    }

    // MARK: - Fuzzy matches

    @Test("A paraphrase that shares distinctive words still finds its segment")
    func matchesParaphraseByTokenOverlap() {
        // No contiguous run of this appears in the transcript; the fallback has
        // to score token overlap across segments.
        #expect(enrich("naming things and cache invalidation are the hardest").timestamp == "1:05")
    }

    @Test("A quote sharing only one ordinary word is left untimed rather than guessed")
    func refusesWeakMatches() {
        // "about" is the sole overlap with segment one, which is below the floor.
        #expect(enrich("Completely unrelated musings about zebras migrating").timestamp == nil)
    }

    @Test("A quote with nothing in common is left untimed")
    func refusesUnrelatedQuote() {
        #expect(enrich("Zebras migrate annually across vast grassland").timestamp == nil)
    }

    // MARK: - Pass-through cases

    @Test("A quote that already carries a timestamp is returned untouched")
    func keepsExistingTimestamp() {
        let quote = enrich("The hardest problem in computing is cache invalidation",
                           timestamp: "9:99")
        #expect(quote.timestamp == "9:99")
    }

    @Test("An empty existing timestamp is treated as missing and gets filled in")
    func replacesEmptyTimestamp() {
        #expect(enrich("cache invalidation", timestamp: "").timestamp == "1:05")
    }

    @Test("With no transcript, every quote comes back exactly as it went in")
    func noSegmentsIsANoOp() {
        let quotes = [
            TimestampedQuote(text: "Anything", timestamp: nil),
            TimestampedQuote(text: "Already timed", timestamp: "1:00"),
        ]
        let result = QuotesFinder.enrich(quotes: quotes, segments: [])

        #expect(result.map(\.text) == ["Anything", "Already timed"])
        #expect(result.map(\.timestamp) == [nil, "1:00"])
    }

    @Test("An empty quote is left alone instead of matching the first segment")
    func emptyQuoteIsNotMatched() {
        #expect(enrich("").timestamp == nil)
        #expect(enrich("   ").timestamp == nil)
    }

    @Test("Enrichment preserves the quotes, their text and their order")
    func preservesQuoteList() {
        let quotes = [
            TimestampedQuote(text: "cache invalidation", timestamp: nil),
            TimestampedQuote(text: "Zebras migrate annually", timestamp: nil),
            TimestampedQuote(text: "thanks for listening everyone", timestamp: nil),
        ]
        let result = QuotesFinder.enrich(quotes: quotes, segments: segments)

        #expect(result.map(\.text) == quotes.map(\.text))
        #expect(result.map(\.timestamp) == ["1:05", nil, "1:02:05"])
    }

    @Test("A matched quote's timestamp parses back to the segment's start time")
    func timestampsAreParseable() throws {
        let quote = enrich("The hardest problem in computing is cache invalidation")
        #expect(try #require(quote.timeInSeconds) == 65)
    }
}
