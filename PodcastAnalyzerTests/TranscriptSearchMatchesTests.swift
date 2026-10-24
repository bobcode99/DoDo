//
//  TranscriptSearchMatchesTests.swift
//  PodcastAnalyzerTests
//
//  The coordinator owns the in-transcript match list: assigning the query is
//  enough for every view reading it to see the same matches.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Transcript search matches")
struct TranscriptSearchMatchesTests {

    private func coordinator(_ lines: [String]) -> TranscriptCoordinator {
        let coordinator = TranscriptCoordinator(
            episode: PodcastEpisodeInfo(title: "Episode"),
            podcastTitle: "Show",
            podcastLanguage: "en"
        )
        coordinator.groupedSentences = lines.enumerated().map { index, line in
            TranscriptSentence(
                id: index,
                segments: [
                    TranscriptSegment(
                        id: index, startTime: TimeInterval(index), endTime: TimeInterval(index + 1), text: line
                    )
                ]
            )
        }
        return coordinator
    }

    @Test("Setting the query lists the matching sentences in transcript order")
    func queryUpdatesMatches() {
        let transcript = coordinator(["Cafe au lait", "Nothing here", "Another café"])
        transcript.transcriptSearchQuery = "cafe"
        #expect(transcript.searchMatches.map(\.id) == [0, 2])
    }

    @Test("Surrounding spaces in the query are ignored")
    func queryIsTrimmed() {
        let transcript = coordinator(["alpha beta", "gamma"])
        transcript.transcriptSearchQuery = "alpha "
        #expect(transcript.searchMatches.map(\.id) == [0])
    }

    @Test("Clearing the query clears the matches and the position")
    func clearingResets() {
        let transcript = coordinator(["alpha", "alpha again"])
        transcript.transcriptSearchQuery = "alpha"
        transcript.currentMatchIndex = 1
        transcript.transcriptSearchQuery = ""
        #expect(transcript.searchMatches.isEmpty)
        #expect(transcript.currentMatchIndex == 0)
    }

    @Test("Changing the query starts again from the first match")
    func newQueryResetsPosition() {
        let transcript = coordinator(["alpha", "alpha again", "beta"])
        transcript.transcriptSearchQuery = "alpha"
        transcript.currentMatchIndex = 1
        transcript.transcriptSearchQuery = "beta"
        #expect(transcript.currentMatchIndex == 0)
        #expect(transcript.searchMatches.map(\.id) == [2])
    }

    @Test("Regrouping keeps the matches in step with the new sentences")
    func regroupRefreshesMatches() {
        let transcript = coordinator([])
        transcript.transcriptSearchQuery = "alpha"
        #expect(transcript.searchMatches.isEmpty)
        transcript.transcriptSegments = [
            TranscriptSegment(id: 1, startTime: 0, endTime: 1, text: "alpha one."),
            TranscriptSegment(id: 2, startTime: 1, endTime: 2, text: "beta two."),
        ]
        transcript.regroupSentences()
        #expect(transcript.searchMatches.map(\.id) == [1])
    }
}
