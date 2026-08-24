//
//  VTTParserTests.swift
//  PodcastAnalyzerTests
//
//  Host-provided transcripts arrive as WebVTT far more often than SRT, and the
//  app converts them once on download and never looks at the original again. So
//  everything this parser drops is dropped permanently: a cue skipped because
//  its block started with a `NOTE`, a caption left reading `<v Bob>Hi` because
//  the tags weren't stripped, or a whole file lost to CRLF line endings.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("WebVTT parsing")
struct VTTParserTests {

    private let minimal = """
    WEBVTT

    00:00:00.000 --> 00:00:02.000
    Hello there.

    00:00:02.000 --> 00:00:04.000
    Second cue.
    """

    // MARK: - Segments

    @Test("A minimal VTT file parses into sequentially numbered segments")
    func parsesMinimalFile() {
        let segments = VTTParser.parseSegments(from: minimal)

        #expect(segments.map(\.id) == [1, 2])
        #expect(segments.map(\.text) == ["Hello there.", "Second cue."])
        #expect(segments.map(\.startTime) == [0, 2])
        #expect(segments.map(\.endTime) == [2, 4])
    }

    @Test("The WEBVTT header is not mistaken for a cue")
    func skipsHeader() {
        let withHeaderMetadata = """
        WEBVTT - Some Title
        Kind: captions
        Language: en

        00:00:01.000 --> 00:00:02.000
        Only cue.
        """

        #expect(VTTParser.parseSegments(from: withHeaderMetadata).map(\.text) == ["Only cue."])
    }

    @Test("NOTE, STYLE and REGION blocks are skipped without eating the next cue")
    func skipsMetadataBlocks() {
        let vtt = """
        WEBVTT

        NOTE This transcript was machine generated.

        STYLE
        ::cue { color: peachpuff; }

        REGION
        id:fred width:40%

        00:00:05.000 --> 00:00:07.000
        Real content.
        """

        let segments = VTTParser.parseSegments(from: vtt)
        #expect(segments.map(\.text) == ["Real content."])
        #expect(segments.map(\.startTime) == [5])
    }

    @Test("A cue identifier line above the timestamp does not become caption text")
    func handlesCueIdentifiers() {
        let vtt = """
        WEBVTT

        intro-cue
        00:00:00.000 --> 00:00:03.000
        The actual line.
        """

        #expect(VTTParser.parseSegments(from: vtt).map(\.text) == ["The actual line."])
    }

    @Test("Windows and classic-Mac line endings parse identically to Unix")
    func normalizesLineEndings() {
        let unix = VTTParser.parseSegments(from: minimal)
        let windows = VTTParser.parseSegments(
            from: minimal.replacingOccurrences(of: "\n", with: "\r\n"))
        let classicMac = VTTParser.parseSegments(
            from: minimal.replacingOccurrences(of: "\n", with: "\r"))

        #expect(windows.map(\.text) == unix.map(\.text))
        #expect(classicMac.map(\.text) == unix.map(\.text))
        #expect(windows.first?.endTime == 2)
    }

    @Test("Both MM:SS and HH:MM:SS timestamp forms are understood")
    func parsesBothTimestampForms() {
        let vtt = """
        WEBVTT

        01:30.500 --> 01:32.000
        Short form.

        01:02:03.000 --> 01:02:04.000
        Long form.
        """

        #expect(VTTParser.parseSegments(from: vtt).map(\.startTime) == [90.5, 3723])
    }

    @Test("Cue settings after the end time are not parsed as part of it")
    func ignoresCueSettings() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000 position:50% line:63% align:middle
        Positioned cue.
        """

        #expect(VTTParser.parseSegments(from: vtt).map(\.endTime) == [2])
    }

    @Test("A cue with an unparseable timestamp is skipped, not zeroed")
    func skipsUnparseableTimestamps() {
        let vtt = """
        WEBVTT

        nonsense --> garbage
        Dropped.

        00:00:01.000 --> 00:00:02.000
        Kept.
        """

        let segments = VTTParser.parseSegments(from: vtt)
        #expect(segments.map(\.text) == ["Kept."])
        // Numbering closes over the gap rather than leaving a hole.
        #expect(segments.map(\.id) == [1])
    }

    @Test("A cue with no text after the timestamp is dropped")
    func skipsEmptyCue() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:01.000

        00:00:01.000 --> 00:00:02.000
        Present.
        """

        #expect(VTTParser.parseSegments(from: vtt).map(\.text) == ["Present."])
    }

    @Test("Empty and non-VTT input parse to nothing rather than failing")
    func handlesEmptyAndGarbage() {
        #expect(VTTParser.parseSegments(from: "").isEmpty)
        #expect(VTTParser.parseSegments(from: "WEBVTT").isEmpty)
        #expect(VTTParser.parseSegments(from: "<html>Not found</html>").isEmpty)
    }

    // MARK: - Tag stripping

    @Test("Voice, class and timestamp tags are stripped from the visible text")
    func stripsTags() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:04.000
        <v Bob Chen><c.loud>Hello</c> <00:00:02.000>there</v>
        """

        #expect(VTTParser.parseSegments(from: vtt).first?.text == "Hello there")
    }

    @Test("HTML entities inside cue text are decoded")
    func decodesEntities() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        It&#39;s Tom &amp; Jerry &hellip;
        """

        #expect(VTTParser.parseSegments(from: vtt).first?.text == "It's Tom & Jerry \u{2026}")
    }

    @Test("A cue that is nothing but markup is dropped rather than left blank")
    func dropsMarkupOnlyCue() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        <v Bob>

        00:00:02.000 --> 00:00:03.000
        Real text.
        """

        #expect(VTTParser.parseSegments(from: vtt).map(\.text) == ["Real text."])
    }

    // MARK: - Speaker names

    @Test("Voice tags surrender their speaker names in first-appearance order")
    func extractsSpeakerNames() {
        let vtt = """
        WEBVTT

        00:00:00.000 --> 00:00:02.000
        <v Alice>Welcome.

        00:00:02.000 --> 00:00:04.000
        <v Bob Chen>Thanks for having me.

        00:00:04.000 --> 00:00:06.000
        <v Alice>Of course.
        """

        #expect(VTTParser.speakerNames(in: vtt) == ["Alice", "Bob Chen"])
    }

    @Test("The same speaker in different casing is credited once")
    func dedupesSpeakerNamesCaseInsensitively() {
        let vtt = "<v Alice>Hi\n<v ALICE>Again"
        #expect(VTTParser.speakerNames(in: vtt) == ["Alice"])
    }

    @Test("A file with no voice tags yields no speakers")
    func noSpeakerNames() {
        #expect(VTTParser.speakerNames(in: minimal).isEmpty)
        #expect(VTTParser.speakerNames(in: "").isEmpty)
    }

    // MARK: - Conversion

    @Test("Conversion to SRT produces a document the SRT parser reads back identically")
    func convertsToSRT() {
        let srt = VTTParser.convertToSRT(minimal)
        let reparsed = SRTParser.parseSegments(from: srt)

        #expect(reparsed.map(\.text) == ["Hello there.", "Second cue."])
        #expect(reparsed.map(\.startTime) == [0, 2])
        #expect(reparsed.map(\.endTime) == [2, 4])
        // SRT uses a comma before the milliseconds; VTT uses a period.
        #expect(srt.contains("00:00:00,000 --> 00:00:02,000"))
    }

    @Test("Converting an empty transcript produces an empty document")
    func convertsEmpty() {
        #expect(VTTParser.convertToSRT("WEBVTT").isEmpty)
    }

    @Test("Plain-text extraction concatenates cues in order")
    func extractsPlainText() {
        #expect(VTTParser.extractPlainText(from: minimal) == "Hello there. Second cue.")
        #expect(VTTParser.extractPlainText(from: "").isEmpty)
    }

    // MARK: - Detection

    @Test("VTT content is recognised by its header, leading whitespace and all")
    func detectsVTTContent() {
        #expect(VTTParser.isVTTContent(minimal))
        #expect(VTTParser.isVTTContent("\n\n  WEBVTT\n\n00:00:00.000 --> 00:00:01.000\nHi"))
        #expect(VTTParser.isVTTContent("1\n00:00:00,000 --> 00:00:01,000\nHi") == false)
        #expect(VTTParser.isVTTContent("") == false)
    }

    @Test("VTT MIME types are recognised regardless of case or parameters")
    func detectsVTTType() {
        #expect(VTTParser.isVTTType("text/vtt"))
        #expect(VTTParser.isVTTType("TEXT/VTT; charset=utf-8"))
        #expect(VTTParser.isVTTType("application/x-subrip") == false)
        #expect(VTTParser.isVTTType("text/html") == false)
    }
}
