//
//  MusicDetectionRangeTests.swift
//  PodcastAnalyzerTests
//
//  Music ranges decide which slices of audio are labelled `[♪ Music]` instead of
//  being fed to Apple Speech, which produces confident nonsense on a theme tune.
//  The classifier itself needs a real audio file and a real ML model, so what is
//  covered here is the part that decides what a range *means*: the half-open
//  interval arithmetic, and the single marker glyph that the SRT annotator and
//  the sentence grouper must both agree on.
//

import Foundation
import Testing

@testable import PodcastAnalyzer

@MainActor
@Suite("Music ranges and markers")
struct MusicDetectionRangeTests {

    private func range(_ start: TimeInterval, _ end: TimeInterval)
    -> MusicDetectionService.TimeRange {
        MusicDetectionService.TimeRange(start: start, end: end)
    }

    // MARK: - Interval arithmetic

    @Test("A range's duration is its span")
    func duration() {
        #expect(range(10, 25).duration == 15)
        #expect(range(0, 0).duration == 0)
    }

    @Test("Overlap is symmetric and only counts a shared interval, not a shared edge")
    func overlap() {
        let intro = range(0, 30)

        #expect(intro.overlaps(with: range(20, 40)))
        #expect(range(20, 40).overlaps(with: intro))
        #expect(intro.overlaps(with: range(5, 10)))   // fully contained
        #expect(intro.overlaps(with: range(40, 50)) == false)
        // Touching at the boundary is not an overlap: the ranges are half-open,
        // so speech starting exactly where music ends is speech.
        #expect(intro.overlaps(with: range(30, 40)) == false)
    }

    @Test("A zero-length range never overlaps itself")
    func emptyRangeDoesNotOverlapItself() {
        #expect(range(10, 10).overlaps(with: range(10, 10)) == false)
    }

    @Test("A zero-length probe strictly inside a range does report an overlap")
    func emptyProbeInsideARange() {
        // Documenting the arithmetic rather than endorsing it: `start < other.end
        // && other.start < end` is true for an empty range in the interior. The
        // classifier never emits empty ranges, so this is a boundary note, not a
        // path the app takes.
        #expect(range(0, 30).overlaps(with: range(10, 10)))
        #expect(range(10, 10).overlaps(with: range(0, 30)))
    }

    @Test("Containment includes the start and excludes the end")
    func containment() {
        let music = range(10, 20)

        #expect(music.contains(10))
        #expect(music.contains(15))
        #expect(music.contains(19.999))
        #expect(music.contains(20) == false)  // the instant speech resumes
        #expect(music.contains(9.999) == false)
    }

    @Test("Ranges compare by value, so the same span is the same range")
    func equality() {
        #expect(range(10, 20) == range(10, 20))
        #expect(range(10, 20) != range(10, 21))
    }

    // MARK: - Markers

    @Test("The marker text carries the single glyph both sides key off")
    func markerText() {
        #expect(MusicDetectionService.markerText.contains(MusicDetectionService.markerGlyph))
        #expect(MusicDetectionService.isMarker(MusicDetectionService.markerText))
    }

    @Test("A marker is recognised even with a caption wrapped around it")
    func recognisesEmbeddedMarker() {
        #expect(MusicDetectionService.isMarker("\(MusicDetectionService.markerText) — theme"))
    }

    @Test("Ordinary speech is never mistaken for a music marker")
    func ordinarySpeechIsNotAMarker() {
        #expect(MusicDetectionService.isMarker("Welcome to the show.") == false)
        #expect(MusicDetectionService.isMarker("") == false)
        // The word "music" alone must not trip it — only the glyph counts.
        #expect(MusicDetectionService.isMarker("Let's talk about music.") == false)
        #expect(MusicDetectionService.isMarker("[Music]") == false)
    }

    // MARK: - Best-effort behaviour

    @Test("An unreadable audio file yields no ranges rather than failing transcription")
    func missingAudioFileIsNotAnError() async {
        // Music detection is an optimisation: if it can't run, transcription
        // must still go ahead with no music markers.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("MusicDetectionRangeTests-\(UUID().uuidString).m4a")

        #expect(await MusicDetectionService.detectMusicRanges(in: missing).isEmpty)
    }

    @Test("A cancelled detection returns empty without paying the ML cost")
    func cancellationReturnsEmpty() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("MusicDetectionRangeTests-\(UUID().uuidString).m4a")

        let task = Task { await MusicDetectionService.detectMusicRanges(in: missing) }
        task.cancel()

        #expect(await task.value.isEmpty)
    }

    @Test("A marker survives being written to SRT and parsed back")
    func markerSurvivesSRTRoundTrip() throws {
        let srt = SRTParser.serialize(segments: [
            TranscriptSegment(id: 1, startTime: 0, endTime: 12,
                              text: MusicDetectionService.markerText),
            TranscriptSegment(id: 2, startTime: 12, endTime: 15, text: "Welcome to the show."),
        ])

        let reparsed = SRTParser.parseSegments(from: srt)
        #expect(reparsed.count == 2)
        #expect(MusicDetectionService.isMarker(try #require(reparsed.first).text))
        #expect(MusicDetectionService.isMarker(try #require(reparsed.last).text) == false)
    }
}
