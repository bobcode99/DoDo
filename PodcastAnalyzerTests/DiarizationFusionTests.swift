//
//  DiarizationFusionTests.swift
//  PodcastAnalyzerTests
//
//  Pins the pure diarization→transcript fusion math (max-overlap speaker
//  assignment, current-speaker lookup, default roster). No engine or SwiftData
//  needed — SpeakerDiarization is Foundation-only.
//

import Testing
@testable import PodcastAnalyzer

@Suite("Speaker diarization fusion")
struct DiarizationFusionTests {

  // spk0 |0───10|      spk1 |10───20|      spk0 |20───30|
  private let turns = [
    SpeakerTurn(start: 0, end: 10, speaker: 0),
    SpeakerTurn(start: 10, end: 20, speaker: 1),
    SpeakerTurn(start: 20, end: 30, speaker: 0),
  ]

  @Test("segment takes the speaker it overlaps most")
  func maxOverlap() {
    // [8,14]: 2s of spk0, 4s of spk1 → spk1
    #expect(SpeakerDiarization.speaker(forStart: 8, end: 14, turns: turns) == 1)
    // [21,29]: fully inside spk0's second turn
    #expect(SpeakerDiarization.speaker(forStart: 21, end: 29, turns: turns) == 0)
    // [0,30]: 20s spk0 vs 10s spk1 → spk0
    #expect(SpeakerDiarization.speaker(forStart: 0, end: 30, turns: turns) == 0)
  }

  @Test("no overlap, empty turns, or zero-width segment yields nil")
  func noOverlap() {
    #expect(SpeakerDiarization.speaker(forStart: 40, end: 50, turns: turns) == nil)
    #expect(SpeakerDiarization.speaker(forStart: 5, end: 8, turns: []) == nil)
    #expect(SpeakerDiarization.speaker(forStart: 5, end: 5, turns: turns) == nil)
  }

  @Test("current-speaker lookup by playback time")
  func atTime() {
    #expect(SpeakerDiarization.speaker(at: 5, turns: turns) == 0)
    #expect(SpeakerDiarization.speaker(at: 15, turns: turns) == 1)
    #expect(SpeakerDiarization.speaker(at: 25, turns: turns) == 0)
    #expect(SpeakerDiarization.speaker(at: 10, turns: turns) == 1)   // boundary: start inclusive
    #expect(SpeakerDiarization.speaker(at: 99, turns: turns) == nil)
  }

  @Test("default roster: one unnamed entry per distinct cluster, ordered")
  func roster() {
    let roster = SpeakerDiarization.defaultRoster(from: turns)
    #expect(roster.map(\.id) == [0, 1])
    #expect(roster.allSatisfy { $0.displayName == nil })
  }
}
