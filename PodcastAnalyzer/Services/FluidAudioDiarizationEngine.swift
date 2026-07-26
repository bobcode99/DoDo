//
//  FluidAudioDiarizationEngine.swift
//  PodcastAnalyzer
//
//  On-device diarization backed by FluidAudio's CoreML Pyannote pipeline
//  (runs on the Neural Engine). Whole file is gated on `canImport(FluidAudio)`
//  so the app builds green before the SPM package is added; adding the package
//  activates this engine automatically via DiarizationService.defaultEngine().
//
//  To enable: Xcode ▸ File ▸ Add Package Dependencies ▸
//  https://github.com/FluidInference/FluidAudio.git — add the FluidAudio
//  product to the PodcastAnalyzer target.
//

#if canImport(FluidAudio)
import Foundation
import FluidAudio

struct FluidAudioDiarizationEngine: DiarizationEngine {
  // nonisolated (see DiarizationEngine): keeps the blocking work below off the
  // main thread under the project's default-MainActor isolation.
  nonisolated func diarize(audioURL: URL) async throws -> [SpeakerTurn] {
    let models = try await DiarizerModels.downloadIfNeeded()
    let diarizer = DiarizerManager()
    diarizer.initialize(models: models)

    // Diarizer wants 16 kHz mono Float samples; AudioConverter handles the
    // decode+resample from the downloaded .mp3.
    let samples = try AudioConverter().resampleAudioFile(audioURL)
    let result = try diarizer.performCompleteDiarization(samples)

    // FluidAudio's `speakerId` may be a String label or a numeric index
    // depending on version. `String(describing:)` + first-appearance interning
    // yields stable 0-based cluster indices either way. `Double(_:)` accepts
    // Float or Double time fields via the BinaryFloatingPoint initializer.
    var clusterIndex: [String: Int] = [:]
    return result.segments.map { segment in
      let key = String(describing: segment.speakerId)
      let idx: Int
      if let existing = clusterIndex[key] {
        idx = existing
      } else {
        idx = clusterIndex.count
        clusterIndex[key] = idx
      }
      return SpeakerTurn(
        start: Double(segment.startTimeSeconds),
        end: Double(segment.endTimeSeconds),
        speaker: idx
      )
    }
  }
}
#endif
