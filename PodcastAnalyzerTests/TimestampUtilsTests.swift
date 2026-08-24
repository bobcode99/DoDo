//
//  TimestampUtilsTests.swift
//  PodcastAnalyzerTests
//
//  AI analysis text is prose with timestamps scattered through it, and the only
//  thing that turns "12:34" into a seek is this regex plus the `pa-timestamp://`
//  URL round trip. The interesting failures are all false positives: a year, a
//  price, a version number, or a chapter marker at 0:00 becoming a tappable link
//  that throws playback somewhere the user never asked to go.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Timestamp parsing and linking")
struct TimestampUtilsTests {

    // MARK: - Parsing

    @Test("MM:SS and H:MM:SS both parse to total seconds")
    func parsesBothForms() {
        #expect(TimestampUtils.parseToSeconds("05:32") == 332)
        #expect(TimestampUtils.parseToSeconds("1:23:45") == 5025)
        #expect(TimestampUtils.parseToSeconds("01:23:45") == 5025)
        #expect(TimestampUtils.parseToSeconds("0:00") == 0)
    }

    @Test("Surrounding brackets and whitespace are stripped before parsing")
    func stripsBracketsAndWhitespace() {
        #expect(TimestampUtils.parseToSeconds("[05:32]") == 332)
        #expect(TimestampUtils.parseToSeconds("  [1:00:00] ") == 3600)
    }

    @Test("Input that isn't a timestamp returns nil rather than zero")
    func rejectsNonTimestamps() {
        #expect(TimestampUtils.parseToSeconds("") == nil)
        #expect(TimestampUtils.parseToSeconds("532") == nil)
        #expect(TimestampUtils.parseToSeconds("abc") == nil)
        #expect(TimestampUtils.parseToSeconds("aa:bb") == nil)
        #expect(TimestampUtils.parseToSeconds("1:2:3:4") == nil)
    }

    @Test("Minute and second fields past 60 are summed as written, not normalised")
    func acceptsOutOfRangeFields() {
        #expect(TimestampUtils.parseToSeconds("90:00") == 5400)
    }

    // MARK: - Finding timestamps in prose

    @Test("Timestamps embedded in prose are found in order")
    func findsTimestampsInProse() {
        let found = TimestampUtils.findTimestamps(
            in: "The guest arrives at 05:32 and the topic shifts at 1:23:45.")

        #expect(found.map(\.text) == ["05:32", "1:23:45"])
        #expect(found.map(\.seconds) == [332, 5025])
    }

    @Test("A repeated timestamp is reported once")
    func dedupesRepeats() {
        let found = TimestampUtils.findTimestamps(in: "See 10:00. Again at 10:00.")
        #expect(found.count == 1)
    }

    @Test("Zero timestamps are ignored, so a 0:00 chapter marker isn't a link")
    func ignoresZero() {
        #expect(TimestampUtils.findTimestamps(in: "Intro at 0:00 and 00:00:00.").isEmpty)
    }

    @Test("Digit runs that merely contain a colon are not timestamps")
    func ignoresNonTimestampDigitRuns() {
        // The lookarounds exist to stop these from matching.
        #expect(TimestampUtils.findTimestamps(in: "12345:67").isEmpty)
        #expect(TimestampUtils.findTimestamps(in: "1:234").isEmpty)
    }

    @Test("Prose with no timestamps yields nothing")
    func findsNothingWhenAbsent() {
        #expect(TimestampUtils.findTimestamps(in: "").isEmpty)
        #expect(TimestampUtils.findTimestamps(in: "No times here at all.").isEmpty)
    }

    // MARK: - Formatting

    @Test("Seconds format as MM:SS below an hour and H:MM:SS above it")
    func formatsSeconds() {
        #expect(TimestampUtils.formatSeconds(0) == "00:00")
        #expect(TimestampUtils.formatSeconds(59) == "00:59")
        #expect(TimestampUtils.formatSeconds(332) == "05:32")
        #expect(TimestampUtils.formatSeconds(3599) == "59:59")
        #expect(TimestampUtils.formatSeconds(3600) == "1:00:00")
        #expect(TimestampUtils.formatSeconds(5025) == "1:23:45")
    }

    @Test("Fractional seconds are truncated, not rounded up past the boundary")
    func truncatesFractions() {
        #expect(TimestampUtils.formatSeconds(59.9) == "00:59")
    }

    @Test("Formatting and parsing are inverses for whole seconds",
          arguments: [1, 59, 60, 332, 3599, 3600, 5025, 86_399])
    func formatParseRoundTrip(_ seconds: Int) {
        let formatted = TimestampUtils.formatSeconds(TimeInterval(seconds))
        #expect(TimestampUtils.parseToSeconds(formatted) == TimeInterval(seconds))
    }

    // MARK: - Link URLs

    @Test("A pa-timestamp URL parses back to the seconds it encodes")
    func parsesTimestampURL() throws {
        let url = try #require(URL(string: "pa-timestamp://332"))
        #expect(TimestampUtils.parseTimestampURL(url) == 332)
    }

    @Test("URLs from another scheme or with a non-numeric host are rejected")
    func rejectsForeignURLs() {
        #expect(TimestampUtils.parseTimestampURL(URL(string: "https://example.com/332")!) == nil)
        #expect(TimestampUtils.parseTimestampURL(URL(string: "pa-timestamp://abc")!) == nil)
        #expect(TimestampUtils.parseTimestampURL(URL(string: "pa-transcript-segment://5")!) == nil)
    }

    @Test("Linkifying prose marks each timestamp and leaves the text untouched")
    func addsLinks() {
        let source = "Arrives at 05:32, leaves at 1:23:45, intro at 0:00."
        let attributed = TimestampUtils.attributedStringWithTimestampLinks(source)

        #expect(String(attributed.characters) == source)

        let links = attributed.runs.compactMap(\.link)
        #expect(links.count == 2)
        #expect(links.contains(URL(string: "pa-timestamp://332")!))
        #expect(links.contains(URL(string: "pa-timestamp://5025")!))
        // 0:00 stays plain — linking it would seek to the start on a stray tap.
        #expect(links.contains(URL(string: "pa-timestamp://0")!) == false)
    }

    @Test("Prose without timestamps comes back unlinked")
    func addsNoLinksWhenAbsent() {
        let attributed = TimestampUtils.attributedStringWithTimestampLinks("Nothing to link.")
        #expect(attributed.runs.compactMap(\.link).isEmpty)
    }
}
