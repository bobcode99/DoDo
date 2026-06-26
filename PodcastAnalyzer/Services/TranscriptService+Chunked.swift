//
//  TranscriptService+Chunked.swift
//  PodcastAnalyzer
//
//  Parallel chunk processing for long audio (≥ 1 minute).
//

import AVFoundation
import Foundation
import OSLog

@available(iOS 26.0, *)
extension TranscriptService {

  /// Transcribes audio using parallel chunks for files ≥ 1 minute.
  /// Falls back to sequential ``audioToSRTWithProgress(inputFile:maxLength:)`` for shorter audio.
  public func audioToSRTChunkedWithProgress(
    inputFile: URL,
    maxLength: Int? = nil,
    chunkDuration: TimeInterval = 300
  ) -> AsyncThrowingStream<TranscriptionProgress, Error> {
    let (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptionProgress.self)
    let task = Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { continuation.finish(); return }
      do {
        let locale = await self.targetLocale
        let censor = await self.censor
        let isCJK = await self.isCJKLocale
        let defaultMaxLen = await self.defaultMaxLength
        let contextualStrings = self.contextualStrings
        let effectiveMaxLength = maxLength ?? defaultMaxLen

        let audioURL = try await self.resolveAudioURL(inputFile)
        let audioFile = try AVAudioFile(forReading: audioURL)
        let sampleRate = audioFile.processingFormat.sampleRate
        let audioFileDuration: TimeInterval =
          sampleRate > 0 ? Double(audioFile.length) / sampleRate : 0

        guard audioFileDuration.isFinite && audioFileDuration > 0 else {
          throw NSError(
            domain: "TranscriptService", code: 12,
            userInfo: [NSLocalizedDescriptionKey: "Invalid audio file duration"])
        }

        self.logger.info("Audio duration: \(audioFileDuration)s — evaluating chunked vs sequential")

        if audioFileDuration < 60 {
          self.logger.info("Audio < 1 min, using sequential processing")
          for try await progress in await self.audioToSRTWithProgress(
            inputFile: inputFile, maxLength: maxLength
          ) {
            continuation.yield(progress)
          }
          continuation.finish()
          return
        }

        continuation.yield(TranscriptionProgress(
          progress: 0.0, currentTimeSeconds: 0,
          totalDurationSeconds: audioFileDuration, isComplete: false, srtContent: nil
        ))

        // Detect music in parallel with chunk export when the global toggle
        // is on. SoundAnalysis is read-only, AVAssetExportSession writes to
        // temp files — they don't contend for the same resource. Music
        // detection typically finishes well before transcription, so the
        // overlap is essentially free.
        let musicDetectionEnabled = await SubtitleSettingsManager.shared.enableMusicDetection
        let musicDetectionConfidence = await SubtitleSettingsManager.shared
          .musicDetectionSensitivity.minimumConfidence
        async let musicRangesTask = Self.detectMusicIfEnabled(
          audioURL: audioURL,
          enabled: musicDetectionEnabled,
          minimumConfidence: musicDetectionConfidence
        )

        self.logger.info("Exporting audio chunks (chunkDuration: \(chunkDuration)s)")
        let overlap: TimeInterval = 2.0
        let chunks = try await ChunkedTranscriptionService.exportAudioChunks(
          from: audioURL, totalDuration: audioFileDuration,
          chunkDuration: chunkDuration, overlap: overlap
        )
        self.logger.info("Exported \(chunks.count) chunks")
        defer { ChunkedTranscriptionService.cleanupTempFiles(chunks) }

        // Announce the part count as soon as it's known so the UI can show
        // "split into N parts" before per-chunk progress starts arriving.
        continuation.yield(TranscriptionProgress(
          progress: 0.0, currentTimeSeconds: 0,
          totalDurationSeconds: audioFileDuration, isComplete: false, srtContent: nil,
          totalParts: chunks.count, completedParts: 0
        ))

        // Apple Speech allows ~2 simultaneous recognition sessions.
        let maxConcurrent = 2
        let progressTracker = ChunkProgressTracker(totalChunks: chunks.count)

        let allChunkResults: [[ChunkedTranscriptionService.ChunkSegment]] =
          try await withThrowingTaskGroup(
            of: (Int, [ChunkedTranscriptionService.ChunkSegment]).self
          ) { group in
            var results = [[ChunkedTranscriptionService.ChunkSegment]](
              repeating: [], count: chunks.count)
            var launched = 0

            for i in 0..<min(maxConcurrent, chunks.count) {
              let chunk = chunks[i]
              let chunkIndex = chunk.index
              group.addTask {
                let segments = try await ChunkedTranscriptionService.transcribeChunkParallel(
                  chunk: chunk, locale: locale, censor: censor, isCJK: isCJK,
                  maxSegmentLength: effectiveMaxLength,
                  contextualStrings: contextualStrings,
                  onProgress: { chunkProgress in
                    let (overall, completed) = progressTracker.updateProgress(
                      chunkIndex: chunkIndex, progress: chunkProgress)
                    continuation.yield(TranscriptionProgress(
                      progress: min(overall, 0.99),
                      currentTimeSeconds: overall * audioFileDuration,
                      totalDurationSeconds: audioFileDuration,
                      isComplete: false, srtContent: nil,
                      totalParts: chunks.count, completedParts: completed
                    ))
                  }
                )
                return (chunkIndex, segments)
              }
              launched += 1
            }

            for try await (chunkIndex, segments) in group {
              results[chunkIndex] = segments
              if launched < chunks.count {
                let chunk = chunks[launched]
                let nextChunkIndex = chunk.index
                group.addTask {
                  let segments = try await ChunkedTranscriptionService.transcribeChunkParallel(
                    chunk: chunk, locale: locale, censor: censor, isCJK: isCJK,
                    maxSegmentLength: effectiveMaxLength,
                    contextualStrings: contextualStrings,
                    onProgress: { chunkProgress in
                      let (overall, completed) = progressTracker.updateProgress(
                        chunkIndex: nextChunkIndex, progress: chunkProgress)
                      continuation.yield(TranscriptionProgress(
                        progress: min(overall, 0.99),
                        currentTimeSeconds: overall * audioFileDuration,
                        totalDurationSeconds: audioFileDuration,
                        isComplete: false, srtContent: nil,
                        totalParts: chunks.count, completedParts: completed
                      ))
                    }
                  )
                  return (nextChunkIndex, segments)
                }
                launched += 1
              }
            }
            return results
          }

        let mergedSegments = ChunkedTranscriptionService.mergeChunkSegments(
          allChunkResults, chunks: chunks)

        // Await the music-detection result (started in parallel above) and
        // splice `[♪ Music]` markers in place of any transcribed segments that
        // fall inside detected music ranges.
        let musicRanges = await musicRangesTask
        if !musicRanges.isEmpty {
          self.logger.info("Detected \(musicRanges.count) music range(s); annotating SRT")
        }
        let annotatedSegments = ChunkedTranscriptionService.annotateMusicSegments(
          speechSegments: mergedSegments,
          musicRanges: musicRanges
        )

        guard !annotatedSegments.isEmpty else {
          throw NSError(
            domain: "TranscriptService", code: 3,
            userInfo: [NSLocalizedDescriptionKey:
              "Transcription produced no content. The audio may be silent or in an unsupported format."])
        }

        let srtContent = SRTFormatter.format(chunkSegments: annotatedSegments)

        continuation.yield(TranscriptionProgress(
          progress: 1.0, currentTimeSeconds: audioFileDuration,
          totalDurationSeconds: audioFileDuration, isComplete: true, srtContent: srtContent,
          totalParts: chunks.count, completedParts: chunks.count
        ))
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }

  /// Runs `MusicDetectionService.detectMusicRanges` only when the global
  /// setting is enabled. Lets the caller use a single `async let` regardless
  /// of the toggle state.
  private static func detectMusicIfEnabled(
    audioURL: URL,
    enabled: Bool,
    minimumConfidence: Double
  ) async -> [MusicDetectionService.TimeRange] {
    guard enabled else { return [] }
    return await MusicDetectionService.detectMusicRanges(
      in: audioURL,
      minimumConfidence: minimumConfidence
    )
  }
}
