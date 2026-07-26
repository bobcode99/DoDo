//
//  DiarizationService.swift
//  PodcastAnalyzer
//
//  Actor seam for speaker diarization. Producers depend on the
//  `DiarizationEngine` protocol, not a concrete engine, so an on-device
//  FluidAudio run and a future server backend are interchangeable — mirroring
//  how TranscriptService keeps ASR engines swappable behind SRT ingestion.
//

import Foundation
import OSLog

/// Normalized diarization result — a speaker timeline, engine-independent.
struct DiarizationOutput: Sendable {
  let turns: [SpeakerTurn]
  var speakerCount: Int { Set(turns.map(\.speaker)).count }
}

/// Anything that turns an audio file into a speaker timeline: FluidAudio
/// on-device, or a server endpoint (reusing the Yap HTTP/SSE plumbing).
protocol DiarizationEngine: Sendable {
  // nonisolated: the project defaults to MainActor isolation, which would
  // otherwise pin the heavy CoreML inference + audio resample to the main
  // thread and freeze the UI. Diarization must run off-main.
  nonisolated func diarize(audioURL: URL) async throws -> [SpeakerTurn]
}

enum DiarizationError: LocalizedError {
  case engineUnavailable

  var errorDescription: String? {
    switch self {
    case .engineUnavailable:
      return "On-device speaker diarization isn't available in this build. "
        + "Add the FluidAudio Swift package to enable it."
    }
  }
}

/// Not-installed placeholder so the app compiles and the seam is exercised
/// before FluidAudio (or a server engine) is wired in.
struct UnavailableDiarizationEngine: DiarizationEngine {
  nonisolated func diarize(audioURL: URL) async throws -> [SpeakerTurn] {
    throw DiarizationError.engineUnavailable
  }
}

actor DiarizationService {
  private let engine: DiarizationEngine
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "Diarization")

  init(engine: DiarizationEngine = DiarizationService.defaultEngine()) {
    self.engine = engine
  }

  /// Best available on-device engine at runtime: FluidAudio when the package is
  /// present, otherwise the unavailable stub. Adding the SPM dependency flips
  /// this on with no other code change.
  static func defaultEngine() -> DiarizationEngine {
    #if canImport(FluidAudio)
    return FluidAudioDiarizationEngine()
    #else
    return UnavailableDiarizationEngine()
    #endif
  }

  func diarize(audioURL: URL) async throws -> DiarizationOutput {
    let turns = try await engine.diarize(audioURL: audioURL)
    let speakers = Set(turns.map(\.speaker)).count
    logger.info(
      "Diarized \(audioURL.lastPathComponent, privacy: .public): \(turns.count) turns, \(speakers) speakers")
    return DiarizationOutput(turns: turns)
  }
}
