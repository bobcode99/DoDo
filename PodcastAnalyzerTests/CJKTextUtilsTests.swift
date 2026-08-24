//
//  CJKTextUtilsTests.swift
//  PodcastAnalyzerTests
//
//  Every transcript joiner in the app runs through `joinTexts`: SRT cue lines,
//  VTT cue lines, and the plain-text builders that feed the AI context. Joining
//  with an unconditional space is the obvious implementation and it is wrong for
//  Chinese, Japanese and Korean — "今天我們" becomes "今天 我們", which is visible
//  in every caption and changes the token count sent to a cloud model.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("CJK-aware text joining")
struct CJKTextUtilsTests {

    // MARK: - Detection

    @Test("Han, kana and Hangul all count as CJK")
    func detectsCJKScripts() {
        #expect(CJKTextUtils.containsCJK("今天"))          // Han
        #expect(CJKTextUtils.containsCJK("ひらがな"))        // Hiragana
        #expect(CJKTextUtils.containsCJK("カタカナ"))        // Katakana
        #expect(CJKTextUtils.containsCJK("한국어"))          // Hangul
    }

    @Test("Latin text, digits and punctuation are not CJK")
    func rejectsNonCJK() {
        #expect(CJKTextUtils.containsCJK("Hello there") == false)
        #expect(CJKTextUtils.containsCJK("12345 !?.,") == false)
        #expect(CJKTextUtils.containsCJK("") == false)
        #expect(CJKTextUtils.containsCJK("🎧") == false)
    }

    @Test("One CJK character anywhere is enough to flag mixed text")
    func detectsMixedText() {
        #expect(CJKTextUtils.containsCJK("Welcome to 台灣"))
    }

    // MARK: - Joining

    @Test("Latin fragments are joined with a space")
    func joinsLatinWithSpace() {
        #expect(CJKTextUtils.joinTexts(["Hello", "there", "friend"]) == "Hello there friend")
    }

    @Test("CJK fragments are joined with nothing between them")
    func joinsCJKWithoutSpace() {
        #expect(CJKTextUtils.joinTexts(["今天我們要談", "關於播客的事情"])
                == "今天我們要談關於播客的事情")
    }

    @Test("A boundary is spaced only when both sides are non-CJK")
    func spacingFollowsTheBoundary() {
        // CJK on the left, Latin on the right: no space.
        #expect(CJKTextUtils.joinTexts(["今天", "podcast"]) == "今天podcast")
        // Latin on the left, CJK on the right: no space either.
        #expect(CJKTextUtils.joinTexts(["podcast", "今天"]) == "podcast今天")
    }

    @Test("The decision looks at the characters either side of the seam, not the whole fragment")
    func decisionIsPerBoundary() {
        // Ends Latin, next starts Latin → spaced, even though CJK is present.
        #expect(CJKTextUtils.joinTexts(["今天 talking", "about 播客"])
                == "今天 talking about 播客")
    }

    @Test("Empty fragments are skipped without leaving a double space")
    func skipsEmptyFragments() {
        #expect(CJKTextUtils.joinTexts(["Hello", "", "there"]) == "Hello there")
        #expect(CJKTextUtils.joinTexts(["今天", "", "我們"]) == "今天我們")
    }

    @Test("Joining nothing or a single fragment is a no-op")
    func handlesDegenerateInput() {
        #expect(CJKTextUtils.joinTexts([]).isEmpty)
        #expect(CJKTextUtils.joinTexts(["only"]) == "only")
        #expect(CJKTextUtils.joinTexts([""]).isEmpty)
    }

    @Test("A leading empty fragment doesn't push a space onto the front")
    func leadingEmptyFragment() {
        #expect(CJKTextUtils.joinTexts(["", "Hello"]) == " Hello")
    }

    // MARK: - Segment links

    @Test("A segment link URL round-trips back to its segment id")
    func segmentLinkRoundTrips() throws {
        let segment = TranscriptSegment(id: 42, startTime: 0, endTime: 1, text: "Hi")
        let url = try #require(TranscriptSegmentLink.url(for: segment))

        #expect(url.scheme == TranscriptSegmentLink.urlScheme)
        #expect(TranscriptSegmentLink.segmentID(from: url) == 42)
    }

    @Test("URLs from another scheme are not treated as segment taps")
    func rejectsForeignSegmentURLs() {
        #expect(TranscriptSegmentLink.segmentID(from: URL(string: "pa-timestamp://42")!) == nil)
        #expect(TranscriptSegmentLink
            .segmentID(from: URL(string: "pa-transcript-segment://abc")!) == nil)
    }
}
