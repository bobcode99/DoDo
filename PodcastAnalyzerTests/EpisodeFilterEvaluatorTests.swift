//
//  EpisodeFilterEvaluatorTests.swift
//  PodcastAnalyzerTests
//
//  The auto-download filter decides, unattended and on cellular, what lands on
//  the device. Both ways of being wrong cost the user something real: a filter
//  that fails open downloads a 3-hour bonus feed nobody asked for, and one that
//  fails closed silently stops downloading a show the user thinks is subscribed.
//
//  The six numbered steps below are the documented decision order (AntennaPod
//  §8); each has a test that fails if the order is rearranged.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Episode auto-download filter")
struct EpisodeFilterEvaluatorTests {

    private func shouldDownload(
        _ title: String,
        duration: TimeInterval = 0,
        include: String = "",
        exclude: String = "",
        minDuration: Int = 0
    ) -> Bool {
        EpisodeFilterEvaluator.shouldAutoDownload(
            episodeTitle: title,
            durationSeconds: duration,
            includeFilter: include,
            excludeFilter: exclude,
            minDurationSeconds: minDuration
        )
    }

    // MARK: - No filters

    @Test("With nothing configured, every episode is accepted")
    func acceptsEverythingByDefault() {
        #expect(shouldDownload("Any Episode"))
        #expect(shouldDownload(""))
    }

    // MARK: - Step 1: duration

    @Test("A known duration below the minimum is rejected")
    func rejectsTooShort() {
        #expect(shouldDownload("Trailer", duration: 60, minDuration: 300) == false)
    }

    @Test("A duration exactly at the minimum is accepted — the bound is inclusive")
    func acceptsExactlyAtMinimum() {
        #expect(shouldDownload("Short Show", duration: 300, minDuration: 300))
    }

    @Test("An unknown duration skips the gate rather than being rejected outright")
    func unknownDurationSkipsGate() {
        // Feeds routinely omit itunes:duration; treating 0 as "too short" would
        // stop auto-download for those shows entirely.
        #expect(shouldDownload("No Duration In Feed", duration: 0, minDuration: 3600))
    }

    @Test("The duration gate runs before the include filter, so a short match is still rejected")
    func durationBeatsInclude() {
        #expect(shouldDownload("Interview Teaser", duration: 30,
                               include: "interview", minDuration: 600) == false)
    }

    // MARK: - Step 2: exclude

    @Test("An excluded term rejects the episode")
    func rejectsExcludedTerm() {
        #expect(shouldDownload("Bonus: Patreon Extra", exclude: "bonus") == false)
    }

    @Test("Exclusion beats inclusion when both match")
    func excludeBeatsInclude() {
        #expect(shouldDownload("Bonus Interview", include: "interview", exclude: "bonus") == false)
    }

    @Test("With only an exclude filter, anything that isn't excluded is accepted")
    func acceptsWhatSurvivesExclusion() {
        #expect(shouldDownload("Regular Episode", exclude: "bonus,trailer"))
    }

    // MARK: - Step 3 & 6: include

    @Test("With an include filter, only matching episodes are accepted")
    func includeActsAsAllowList() {
        #expect(shouldDownload("The Big Interview", include: "interview"))
        #expect(shouldDownload("Weekly Roundup", include: "interview") == false)
    }

    @Test("Any one of several included terms is enough")
    func includeMatchesAnyTerm() {
        #expect(shouldDownload("Weekly Roundup", include: "interview, roundup"))
    }

    // MARK: - Step 5: min duration only

    @Test("With only a minimum duration, a long-enough episode is accepted")
    func minDurationOnlyAccepts() {
        #expect(shouldDownload("Full Episode", duration: 3600, minDuration: 600))
    }

    // MARK: - Term matching

    @Test("Matching ignores case in both the filter and the title")
    func matchingIsCaseInsensitive() {
        #expect(shouldDownload("BONUS ROUND", exclude: "bonus") == false)
        #expect(shouldDownload("bonus round", exclude: "BONUS") == false)
    }

    @Test("A term matches as a substring, not only a whole word")
    func matchesSubstrings() {
        #expect(shouldDownload("Rebroadcast", include: "broadcast"))
    }

    @Test("An episode with an empty title can still be excluded or fail an include filter")
    func handlesEmptyTitle() {
        #expect(shouldDownload("", include: "interview") == false)
        #expect(shouldDownload("", exclude: "bonus"))
    }

    // MARK: - Term parsing

    @Test("Terms are comma-separated, trimmed and lowercased")
    func parsesSimpleTerms() {
        #expect(EpisodeFilterEvaluator.parseTerms("Bonus,  Trailer ,Q&A")
                == ["bonus", "trailer", "q&a"])
    }

    @Test("Surrounding quotes are stripped so a phrase stays one term")
    func parsesQuotedPhrases() {
        #expect(EpisodeFilterEvaluator.parseTerms(#"one, "multi word", three"#)
                == ["one", "multi word", "three"])
    }

    @Test("Blank, whitespace-only and empty-between-commas input contribute no terms")
    func parsesEmptyInput() {
        #expect(EpisodeFilterEvaluator.parseTerms("").isEmpty)
        #expect(EpisodeFilterEvaluator.parseTerms("   ").isEmpty)
        #expect(EpisodeFilterEvaluator.parseTerms(",,").isEmpty)
        #expect(EpisodeFilterEvaluator.parseTerms(#""""#).isEmpty)
    }

    @Test("A filter that parses to no terms behaves as if it were unset")
    func whitespaceFilterIsNotAFilter() {
        #expect(shouldDownload("Anything", include: "   "))
        #expect(shouldDownload("Anything", include: ", ,"))
    }

    @Test("A quoted phrase is matched as the phrase, not its pieces")
    func quotedPhraseMatchesAsPhrase() {
        #expect(shouldDownload("Live From Chicago", include: #""live from""#))
        #expect(shouldDownload("Live Chicago", include: #""live from""#) == false)
    }
}
