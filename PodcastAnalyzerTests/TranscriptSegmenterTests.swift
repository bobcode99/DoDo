//
//  TranscriptSegmenterTests.swift
//  PodcastAnalyzerTests
//
//  Apple Speech returns one continuous run of text; the segmenter is what turns
//  it into subtitle-sized pieces. Two failure modes are invisible in a diff and
//  obvious on screen: a segment far longer than the cap (a wall of text over the
//  artwork), and text quietly dropped at a split boundary — the transcript is
//  still fluent, just missing a clause, which no length assertion would catch.
//
//  CJK gets its own path because there are no spaces to break on: the clause
//  marks (，、；：) are the only natural pause points available.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Transcript segmentation")
struct TranscriptSegmenterTests {

    private func segments(
        _ text: String, isCJK: Bool, maxLength: Int
    ) -> [String] {
        let transcript = AttributedString(text)
        let segmenter = TranscriptSegmenter(isCJK: isCJK, maxLength: maxLength)
        return segmenter.computeSegmentRanges(transcript: transcript)
            .map { String(transcript[$0].characters) }
    }

    /// Text with all whitespace removed — the comparison that survives a split
    /// boundary swallowing a space.
    private func condensed(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).joined()
    }

    // MARK: - Short input

    @Test("A sentence inside the cap is left as one segment")
    func shortSentenceIsNotSplit() {
        #expect(segments("Hello there.", isCJK: false, maxLength: 40) == ["Hello there."])
    }

    @Test("Each sentence becomes its own segment")
    func sentencesAreSeparated() {
        let result = segments("First one. Second one. Third one.", isCJK: false, maxLength: 40)
        #expect(result.count == 3)
        #expect(result.first?.contains("First one.") == true)
        #expect(result.last?.contains("Third one.") == true)
    }

    @Test("Empty input produces no segments")
    func emptyInput() {
        #expect(segments("", isCJK: false, maxLength: 40).isEmpty)
        #expect(segments("", isCJK: true, maxLength: 10).isEmpty)
    }

    @Test("Whitespace-only input produces nothing to display")
    func whitespaceOnlyInput() {
        let result = segments("   \n  ", isCJK: false, maxLength: 40)
        #expect(result.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    // MARK: - Word splitting

    @Test("A long sentence is broken into pieces that respect the cap")
    func longSentenceIsSplitByWords() {
        let text = "The quick brown fox jumps over the lazy dog near the river bank today."
        let result = segments(text, isCJK: false, maxLength: 20)

        #expect(result.count > 1)
        for segment in result {
            #expect(segment.count <= 20, "segment too long: \(segment)")
        }
    }

    @Test("Splitting by words never loses text")
    func wordSplittingIsLossless() {
        let text = "The quick brown fox jumps over the lazy dog near the river bank today."
        let result = segments(text, isCJK: false, maxLength: 20)

        #expect(condensed(result.joined()) == condensed(text))
    }

    @Test("A single word longer than the cap is kept whole rather than cut mid-word")
    func oversizedWordSurvives() {
        let text = "Antidisestablishmentarianism follows."
        let result = segments(text, isCJK: false, maxLength: 10)

        #expect(result.contains { $0.contains("Antidisestablishmentarianism") })
        #expect(condensed(result.joined()) == condensed(text))
    }

    // MARK: - CJK clause splitting

    @Test("A long CJK sentence breaks at its clause marks")
    func cjkSplitsAtClauseMarkers() {
        let text = "今天我們要談播客，還有技術細節，最後是問答。"
        let result = segments(text, isCJK: true, maxLength: 10)

        #expect(result.count > 1)
        // Each clause keeps the mark that ended it, so the break reads naturally.
        #expect(result.first?.hasSuffix("，") == true)
    }

    @Test("Clause splitting never loses a character")
    func cjkSplittingIsLossless() {
        let text = "今天我們要談播客，還有技術細節，最後是問答。"
        let result = segments(text, isCJK: true, maxLength: 10)

        #expect(result.joined() == text)
    }

    @Test("A CJK clause with no punctuation to break on still gets divided")
    func cjkFallsBackToWordSplitting() {
        // One 30-character run with no clause marks at all.
        let text = String(repeating: "今天我們要談論播客製作", count: 3) + "。"
        let result = segments(text, isCJK: true, maxLength: 10)

        #expect(result.count > 1)
        #expect(condensed(result.joined()) == condensed(text))
    }

    @Test("Small adjacent clauses are merged rather than each becoming a flash of text")
    func smallClausesMerge() {
        let text = "好，對，是的，我明白了，我們繼續下去吧。"
        let result = segments(text, isCJK: true, maxLength: 12)

        // Without merging this would be five one- or two-character segments.
        #expect(result.count < 5)
        #expect(result.joined() == text)
        for segment in result {
            #expect(segment.count <= 12, "segment too long: \(segment)")
        }
    }

    @Test("The same text splits differently depending on the CJK flag")
    func cjkFlagChangesTheStrategy() {
        let text = "今天我們要談播客，還有技術細節，最後是問答。"
        #expect(segments(text, isCJK: true, maxLength: 10)
                != segments(text, isCJK: false, maxLength: 10))
    }

    @Test("ASCII commas are accepted as clause marks, since some transcripts use them")
    func asciiClauseMarkersCount() {
        #expect(TranscriptSegmenter.clauseMarkers.contains(","))
        #expect(TranscriptSegmenter.clauseMarkers.contains("，"))
        #expect(TranscriptSegmenter.clauseMarkers.contains(";"))
        #expect(TranscriptSegmenter.clauseMarkers.contains("。") == false)
    }

    // MARK: - Sentence endings

    @Test("Sentence terminators are recognised in both scripts")
    func detectsSentenceEnds() {
        let segmenter = TranscriptSegmenter(isCJK: false, maxLength: 40)

        #expect(segmenter.isSentenceEnd("Done."))
        #expect(segmenter.isSentenceEnd("Really?"))
        #expect(segmenter.isSentenceEnd("Wow!"))
        #expect(segmenter.isSentenceEnd("結束了。"))
        #expect(segmenter.isSentenceEnd("是嗎？"))
        #expect(segmenter.isSentenceEnd("好！"))
    }

    @Test("Trailing whitespace doesn't hide a sentence ending")
    func ignoresTrailingWhitespace() {
        #expect(TranscriptSegmenter(isCJK: false, maxLength: 40).isSentenceEnd("Done.  \n"))
    }

    @Test("Mid-sentence text and empty text are not sentence endings")
    func rejectsNonEndings() {
        let segmenter = TranscriptSegmenter(isCJK: false, maxLength: 40)

        #expect(segmenter.isSentenceEnd("and then") == false)
        #expect(segmenter.isSentenceEnd("") == false)
        #expect(segmenter.isSentenceEnd("   ") == false)
        #expect(segmenter.isSentenceEnd("一半，") == false)
    }
}
