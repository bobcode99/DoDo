//
//  ChunkedTranscriptionService.swift
//  PodcastAnalyzer
//
//  Extracted from TranscriptService.swift — parallel chunk processing.
//

import AVFoundation
import Foundation
import Speech
import Synchronization

@available(iOS 26.0, *)
nonisolated enum ChunkedTranscriptionService {

  /// Represents an audio chunk for parallel transcription
  struct AudioChunk: Sendable {
    let index: Int
    let fileURL: URL
    let startTime: Double
    let endTime: Double
  }

  /// A single transcribed segment from a chunk, with timestamps offset to the original timeline
  struct ChunkSegment: Sendable {
    let startTime: Double
    let endTime: Double
    let text: String
  }

  /// Splits an audio file into time-ranged chunks for parallel processing.
  /// Uses `AVAssetExportSession` to export each chunk as M4A.
  static func exportAudioChunks(
    from sourceURL: URL,
    totalDuration: TimeInterval,
    chunkDuration: TimeInterval = 300,
    overlap: TimeInterval = 2.0
  ) async throws -> [AudioChunk] {
    let asset = AVURLAsset(url: sourceURL)
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("TranscriptChunks-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    // Calculate chunk time ranges
    var chunkRanges: [(index: Int, start: Double, end: Double)] = []
    var chunkStart: Double = 0
    var index = 0
    while chunkStart < totalDuration {
      let chunkEnd = min(chunkStart + chunkDuration, totalDuration)
      chunkRanges.append((index: index, start: chunkStart, end: chunkEnd))
      chunkStart = chunkEnd - overlap
      if chunkEnd >= totalDuration { break }
      index += 1
    }

    // Export chunks concurrently (export is I/O-bound, not CPU-bound)
    return try await withThrowingTaskGroup(of: AudioChunk.self) { group in
      for range in chunkRanges {
        group.addTask {
          let outputURL = tempDir.appendingPathComponent("chunk_\(range.index).m4a")

          guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
          ) else {
            throw NSError(
              domain: "TranscriptService", code: 10,
              userInfo: [NSLocalizedDescriptionKey: "Failed to create export session for chunk \(range.index)"]
            )
          }

          exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: range.start, preferredTimescale: 44100),
            end: CMTime(seconds: range.end, preferredTimescale: 44100)
          )

          try await exportSession.export(to: outputURL, as: .m4a)

          return AudioChunk(
            index: range.index,
            fileURL: outputURL,
            startTime: range.start,
            endTime: range.end
          )
        }
      }

      var chunks: [AudioChunk] = []
      for try await chunk in group {
        chunks.append(chunk)
      }
      return chunks.sorted { $0.index < $1.index }
    }
  }

  /// Transcribes a single audio chunk. Creates its own SpeechTranscriber/SpeechAnalyzer
  /// for true parallel execution across chunks.
  static func transcribeChunkParallel(
    chunk: AudioChunk,
    locale: Locale,
    censor: Bool,
    isCJK: Bool,
    maxSegmentLength: Int,
    contextualStrings: [String],
    onProgress: @Sendable (Double) -> Void
  ) async throws -> [ChunkSegment] {
    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: censor ? [.etiquetteReplacements] : [],
      reportingOptions: [],
      attributeOptions: [.audioTimeRange]
    )
    let analyzer = SpeechAnalyzer(modules: [transcriber])

    // Bias recognition toward this show's proper nouns / jargon (per-podcast
    // Transcription Context). Best-effort: a context failure must not fail the
    // chunk. Must be set before `analyzer.start`.
    if !contextualStrings.isEmpty {
      let context = AnalysisContext()
      context.contextualStrings = [.general: contextualStrings]
      try? await analyzer.setContext(context)
    }

    let audioFile = try AVAudioFile(forReading: chunk.fileURL)
    try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

    let chunkDuration = chunk.endTime - chunk.startTime
    var transcript: AttributedString = ""
    var lastProgressReport = Date.distantPast

    for try await result in transcriber.results {
      transcript += result.text

      // Report incremental progress, throttled to ~2 updates/sec
      let now = Date()
      if now.timeIntervalSince(lastProgressReport) >= 0.5 {
        for run in result.text.runs {
          if let timeRange = run.audioTimeRange {
            let seconds = timeRange.end.seconds
            if seconds.isFinite && chunkDuration > 0 {
              onProgress(min(seconds / chunkDuration, 1.0))
              lastProgressReport = now
              break
            }
          }
        }
      }
    }

    // Mark chunk fully transcribed
    onProgress(1.0)

    guard !transcript.characters.isEmpty else { return [] }

    // Apply Chinese punctuation restoration for CJK locales
    if isCJK {
      transcript = ChinesePunctuationRestorer().restore(transcript: transcript)
    }

    // Reuse the shared segmenter (NLTokenizer sentence/word boundaries + CJK
    // clause splitting) rather than a separate hand-rolled run-grouping loop, so
    // chunked transcripts break the same way as short sequential ones. The
    // segmenter's time ranges are chunk-relative; offset them onto the global
    // timeline with `chunk.startTime`.
    let segmenter = TranscriptSegmenter(isCJK: isCJK, maxLength: maxSegmentLength)
    return segmenter.splitTranscriptIntoSegments(transcript: transcript).compactMap { segment in
      guard let timeRange = segment.audioTimeRange else { return nil }
      let text = String(segment.characters).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      let start = timeRange.start.seconds
      let end = timeRange.end.seconds
      guard start.isFinite, end.isFinite else { return nil }
      return ChunkSegment(
        startTime: start + chunk.startTime,
        endTime: end + chunk.startTime,
        text: text
      )
    }
  }

  /// Merges segment results from multiple chunks, de-duplicating the
  /// overlap-region audio (which both chunks transcribed).
  ///
  /// Earlier chunks own the overlap region: for chunk N+1, anything whose
  /// startTime is before `chunks[N].endTime` (the previous chunk's nominal
  /// end) was already produced by chunk N and is discarded here.
  ///
  /// Why nominal end and not last-segment end: a previous version used the
  /// last segment's `endTime`, which is well below the chunk boundary when
  /// speech ends mid-chunk and right at it when speech runs into the
  /// overlap. The latter case let duplicate boundary segments survive,
  /// producing repeated words with offset timestamps.
  static func mergeChunkSegments(
    _ chunkResults: [[ChunkSegment]],
    chunks: [AudioChunk]
  ) -> [ChunkSegment] {
    guard !chunkResults.isEmpty else { return [] }
    guard chunkResults.count > 1 else { return chunkResults[0] }

    var merged: [ChunkSegment] = []

    for (chunkIndex, segments) in chunkResults.enumerated() {
      if chunkIndex == 0 {
        merged.append(contentsOf: segments)
      } else {
        let previousChunkEnd = chunks[chunkIndex - 1].endTime
        for segment in segments where segment.startTime >= previousChunkEnd {
          merged.append(segment)
        }
      }
    }

    merged.sort { $0.startTime < $1.startTime }
    return merged
  }

  /// Replaces transcribed segments that fall mostly inside detected music
  /// ranges with explicit `[♪ Music]` marker segments. Apple Speech produces
  /// garbage on pure music; this keeps the SRT honest by dropping those
  /// segments and surfacing the music ranges directly.
  ///
  /// A segment is dropped when `musicOverlapRatio` (≥ 0.7 by default) of its
  /// duration lies inside any music range. The previous midpoint-only check
  /// dropped real speech that crossed a music boundary (e.g. host starting to
  /// talk before the intro music tag fully ended).
  static func annotateMusicSegments(
    speechSegments: [ChunkSegment],
    musicRanges: [MusicDetectionService.TimeRange],
    marker: String = MusicDetectionService.markerText,
    musicOverlapRatio: Double = 0.7
  ) -> [ChunkSegment] {
    guard !musicRanges.isEmpty else { return speechSegments }

    let speechOnly = speechSegments.filter { segment in
      let duration = max(segment.endTime - segment.startTime, 0.001)
      let overlap = musicRanges.reduce(0.0) { acc, range in
        acc + max(0, min(segment.endTime, range.end) - max(segment.startTime, range.start))
      }
      return overlap / duration < musicOverlapRatio
    }

    let markers = musicRanges.map { range in
      ChunkSegment(startTime: range.start, endTime: range.end, text: marker)
    }

    return (speechOnly + markers).sorted { $0.startTime < $1.startTime }
  }

  /// Removes temporary chunk files
  static func cleanupTempFiles(_ chunks: [AudioChunk]) {
    for chunk in chunks {
      try? FileManager.default.removeItem(at: chunk.fileURL)
    }
    if let firstChunk = chunks.first {
      try? FileManager.default.removeItem(at: firstChunk.fileURL.deletingLastPathComponent())
    }
  }
}

/// Thread-safe progress tracker for parallel chunk processing.
/// Uses Mutex instead of actor to allow synchronous access from onProgress callbacks,
/// eliminating the need for unstructured Task {} per progress update.
@available(iOS 26.0, *)
nonisolated final class ChunkProgressTracker: Sendable {
  private let totalChunks: Int
  private let state: Mutex<[Int: Double]>

  init(totalChunks: Int) {
    self.totalChunks = totalChunks
    self.state = Mutex([:])
  }

  /// Updates progress for a specific chunk and returns the overall progress (0.0–1.0)
  func updateProgress(chunkIndex: Int, progress: Double) -> Double {
    state.withLock { progresses in
      progresses[chunkIndex] = progress
      return progresses.values.reduce(0, +) / Double(totalChunks)
    }
  }
}
