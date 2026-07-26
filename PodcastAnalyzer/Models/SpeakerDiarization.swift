//
//  SpeakerDiarization.swift
//  PodcastAnalyzer
//
//  Speaker-layer value types + the pure fusion math that maps a diarization
//  timeline onto transcript segments. Kept engine-agnostic and Foundation-only
//  so it's unit-testable without the diarization engine (FluidAudio / server).
//

import Foundation

/// One diarized window: a continuous stretch of audio attributed to a single
/// speaker cluster. Engine-agnostic (RTTM-equivalent) — a local FluidAudio run
/// and a server both normalize to this. `speaker` is an anonymous cluster index
/// (0, 1, 2…); human names live in the roster, not here, so re-diarizing never
/// disturbs naming and vice-versa.
nonisolated struct SpeakerTurn: Codable, Sendable, Equatable {
  let start: Double
  let end: Double
  let speaker: Int
}

/// Roster entry mapping a cluster index to a user-facing label. Phase-1 leaves
/// `displayName` nil (UI renders "Speaker N"); tap-to-name and voiceprint
/// matching fill it in later. `profileId` links to a cross-episode voiceprint.
nonisolated struct SpeakerLabel: Codable, Sendable, Equatable {
  let id: Int
  var displayName: String?
  var color: Int?
  var profileId: UUID?
}

nonisolated enum SpeakerDiarization {
  /// Assigns a transcript segment its speaker by maximum time overlap against
  /// the diarization turns — the standard ASR+diarization alignment. Returns
  /// nil when no turn overlaps the segment (music/silence the diarizer skipped).
  static func speaker(forStart start: Double, end: Double, turns: [SpeakerTurn]) -> Int? {
    guard start < end, !turns.isEmpty else { return nil }
    var overlapBySpeaker: [Int: Double] = [:]
    for turn in turns {
      let overlap = min(end, turn.end) - max(start, turn.start)
      if overlap > 0 { overlapBySpeaker[turn.speaker, default: 0] += overlap }
    }
    // Tie-break on lowest speaker index for determinism.
    return overlapBySpeaker.max { a, b in
      a.value != b.value ? a.value < b.value : a.key > b.key
    }?.key
  }

  /// Speaker active at playback time `t` — powers the "who's talking now" chip.
  // ponytail: linear scan; fine for typical turn counts, swap to binary search
  // on start time if a multi-hour episode's turn list ever drags the player.
  static func speaker(at t: Double, turns: [SpeakerTurn]) -> Int? {
    turns.first { t >= $0.start && t < $0.end }?.speaker
  }

  /// Default roster straight from raw turns: one unnamed entry per distinct
  /// cluster, ordered by index.
  static func defaultRoster(from turns: [SpeakerTurn]) -> [SpeakerLabel] {
    Set(turns.map(\.speaker)).sorted().map {
      SpeakerLabel(id: $0, displayName: nil, color: nil, profileId: nil)
    }
  }
}
