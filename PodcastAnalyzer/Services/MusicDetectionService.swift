//
//  MusicDetectionService.swift
//  PodcastAnalyzer
//
//  Pre-transcription pass that uses SoundAnalysis' built-in classifier to
//  detect music / singing ranges in an audio file. The chunked transcription
//  pipeline keeps every transcribed line and marks the ones inside those
//  ranges with "♪ ", so the viewer can fade or hide them.
//

import Foundation
import SoundAnalysis
import OSLog
import AVFoundation

nonisolated enum MusicDetectionService {

  private static let logger = Logger(
    subsystem: "com.podcast.analyzer",
    category: "MusicDetection"
  )

  // MARK: - Marker

  /// The note glyph used to identify a music marker segment. Centralized so
  /// the SRT annotator and the sentence grouper agree on the single token.
  static let markerGlyph: Character = "\u{266A}"

  /// Placeholder line for a music stretch where nothing was transcribed.
  static let markerText = "[\(markerGlyph) Music]"

  /// Prefix on a transcribed line that falls inside music. The usual subtitle
  /// convention, so it reads fine in an exported SRT.
  static let musicLinePrefix = "\(markerGlyph) "

  /// True if `text` is a `[♪ Music]` placeholder.
  static func isMarker(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespaces).hasPrefix("[\(markerGlyph)")
  }

  /// True if `text` is a transcribed line marked as inside music.
  static func isMusicLine(_ text: String) -> Bool {
    text.trimmingCharacters(in: .whitespaces).hasPrefix(musicLinePrefix)
  }

  /// `text` without the music-line prefix.
  static func stripMusicPrefix(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    return trimmed.hasPrefix(musicLinePrefix)
      ? String(trimmed.dropFirst(musicLinePrefix.count))
      : text
  }

  /// Whether one classifier window counts as music. A window where speech is
  /// also clearly present is someone talking over a music bed, not music.
  static func isMusicWindow(
    _ scores: [String: Double],
    minimumConfidence: Double,
    speechCeiling: Double = 0.5
  ) -> Bool {
    let speech = scores["speech"] ?? 0
    guard speech < speechCeiling else { return false }
    return scores.contains { label, confidence in
      let label = label.lowercased()
      return (label.contains("music") || label.contains("singing")) && confidence >= minimumConfidence
    }
  }

  // MARK: - Types

  /// Inclusive-start, exclusive-end time range in seconds along the original
  /// audio timeline.
  struct TimeRange: Sendable, Equatable {
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval { end - start }

    func overlaps(with other: TimeRange) -> Bool {
      start < other.end && other.start < end
    }

    func contains(_ time: TimeInterval) -> Bool {
      time >= start && time < end
    }
  }

  // MARK: - Public API

  /// Detect music / singing ranges in `audioURL`. Returns merged ranges
  /// (adjacent hits within ~0.5s are coalesced). Returns an empty array on
  /// failure — music detection is best-effort and must not block
  /// transcription.
  ///
  /// Respects task cancellation at entry: SoundAnalysis itself is not
  /// cancellable, but checking here lets a caller cancel before paying the
  /// ML cost when cancellation arrived during a previous suspension.
  static func detectMusicRanges(
    in audioURL: URL,
    minimumConfidence: Double = 0.6
  ) async -> [TimeRange] {
    guard !Task.isCancelled else { return [] }

    let observer = ClassificationObserver(minimumConfidence: minimumConfidence)
    do {
      let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
      let analyzer = try SNAudioFileAnalyzer(url: audioURL)
      try analyzer.add(request, withObserver: observer)
      await analyzer.analyze()
    } catch {
      logger.warning("Music detection failed (continuing without): \(error.localizedDescription, privacy: .public)")
      return []
    }
    let ranges = await observer.finish()
    logger.info("Detected \(ranges.count) music range(s)")
    return ranges
  }
}

// MARK: - SoundAnalysis observer

/// Bridges the Objective-C `SNResultsObserving` callback model to async/await
/// and accumulates music classification hits along the way.
///
/// Threading: SoundAnalysis serializes all observer callbacks on its own
/// private queue, so `hits`, `finalResult`, and `continuation` are touched
/// from a single queue during analysis. The caller must `await analyze()`
/// before calling `finish()` — that ordering is the only contract.
///
/// The `guard finalResult == nil` in `complete()` makes the at-most-once
/// resume explicit, so a stray double callback from the framework (e.g. both
/// `didFailWithError` and `requestDidComplete`) is a no-op rather than a
/// continuation crash.
private nonisolated final class ClassificationObserver: NSObject, SNResultsObserving, @unchecked Sendable {
  private let minimumConfidence: Double
  private var hits: [MusicDetectionService.TimeRange] = []
  private var continuation: CheckedContinuation<[MusicDetectionService.TimeRange], Never>?
  private var finalResult: [MusicDetectionService.TimeRange]?

  init(minimumConfidence: Double) {
    self.minimumConfidence = minimumConfidence
  }

  func request(_ request: SNRequest, didProduce result: SNResult) {
    guard let result = result as? SNClassificationResult else { return }
    let scores = Dictionary(
      result.classifications.map { ($0.identifier, $0.confidence) },
      uniquingKeysWith: max)
    guard MusicDetectionService.isMusicWindow(scores, minimumConfidence: minimumConfidence) else { return }

    let range = MusicDetectionService.TimeRange(
      start: result.timeRange.start.seconds,
      end: result.timeRange.end.seconds
    )
    hits.append(range)
  }

  func request(_ request: SNRequest, didFailWithError error: Error) {
    complete()
  }

  func requestDidComplete(_ request: SNRequest) {
    complete()
  }

  func finish() async -> [MusicDetectionService.TimeRange] {
    await withCheckedContinuation { cc in
      if let finalResult {
        cc.resume(returning: finalResult)
      } else {
        self.continuation = cc
      }
    }
  }

  // MARK: - Internal

  private func complete() {
    // First completion wins. Guards against SoundAnalysis firing both
    // `didFailWithError` and `requestDidComplete` (which would otherwise
    // double-resume the continuation and crash).
    guard finalResult == nil else { return }
    let merged = Self.merge(hits)
    finalResult = merged
    continuation?.resume(returning: merged)
    continuation = nil
  }

  /// Coalesces adjacent ranges (gap ≤ 0.5s) into a single range so the SRT
  /// doesn't end up with hundreds of micro music markers.
  private static func merge(_ ranges: [MusicDetectionService.TimeRange]) -> [MusicDetectionService.TimeRange] {
    let sorted = ranges.sorted { $0.start < $1.start }
    guard var current = sorted.first else { return [] }

    var merged: [MusicDetectionService.TimeRange] = []
    for range in sorted.dropFirst() {
      if range.start <= current.end + 0.5 {
        current = MusicDetectionService.TimeRange(
          start: current.start,
          end: max(current.end, range.end)
        )
      } else {
        merged.append(current)
        current = range
      }
    }
    merged.append(current)
    return merged
  }
}
