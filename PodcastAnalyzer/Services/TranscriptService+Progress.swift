//
//  TranscriptService+Progress.swift
//  PodcastAnalyzer
//
//  Streaming transcription with real-time progress updates.
//

import Foundation
import Speech
import OSLog
import AVFoundation

@available(iOS 26.0, *)
extension TranscriptService {

  // MARK: - TranscriptionProgress

  /// A single progress snapshot during transcription.
  public struct TranscriptionProgress: Sendable {
    public let progress: Double
    public let currentTimeSeconds: TimeInterval
    public let totalDurationSeconds: TimeInterval
    public let isComplete: Bool
    /// Set only when `isComplete == true`.
    public let srtContent: String?
    /// How many parallel parts the audio was split into (1 = single pass).
    public var totalParts: Int = 1
    /// How many of those parts have fully finished transcribing.
    public var completedParts: Int = 0
  }

  // MARK: - Streaming SRT

  /// Transcribes an audio file to SRT, streaming ``TranscriptionProgress`` updates.
  public func audioToSRTWithProgress(
    inputFile: URL,
    maxLength: Int? = nil
  ) -> AsyncThrowingStream<TranscriptionProgress, Error> {
    let (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptionProgress.self)
    let task = Task.detached(priority: .userInitiated) { [weak self] in
      guard let self else { continuation.finish(); return }
      do {
        let (transcriber, analyzer, needsAudioTimeRange) = await (
          self.transcriber, self.analyzer, self.needsAudioTimeRange
        )
        let isCJK = await self.isCJKLocale
        let defaultMaxLen = await self.defaultMaxLength

        guard let transcriber, let analyzer else {
          throw NSError(
            domain: "TranscriptService", code: 1,
            userInfo: [NSLocalizedDescriptionKey:
              "Transcriber or analyzer not initialized. Call setupAndInstallAssets() first."])
        }
        guard needsAudioTimeRange else {
          throw NSError(
            domain: "TranscriptService", code: 2,
            userInfo: [NSLocalizedDescriptionKey:
              "audioTimeRange must be enabled to generate SRT subtitles."])
        }

        let audioURL = try await self.resolveAudioURL(inputFile)
        let audioFile = try AVAudioFile(forReading: audioURL)
        let audioFileDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        self.logger.info("Audio duration (progress): \(audioFileDuration)s")

        continuation.yield(TranscriptionProgress(
          progress: 0.0,
          currentTimeSeconds: 0,
          totalDurationSeconds: audioFileDuration,
          isComplete: false,
          srtContent: nil
        ))

        try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

        var transcript: AttributedString = ""
        var lastReportedTime: TimeInterval = 0
        var lastProgressDate = Date.distantPast

        for try await result in transcriber.results {
          transcript += result.text

          let now = Date()
          guard now.timeIntervalSince(lastProgressDate) >= 0.5 else { continue }

          for run in result.text.runs {
            if let timeRange = run.audioTimeRange {
              let currentTime = timeRange.end.seconds
              if currentTime > lastReportedTime {
                lastReportedTime = currentTime
                lastProgressDate = now
                continuation.yield(TranscriptionProgress(
                  progress: min(currentTime / audioFileDuration, 0.99),
                  currentTimeSeconds: currentTime,
                  totalDurationSeconds: audioFileDuration,
                  isComplete: false,
                  srtContent: nil
                ))
                break
              }
            }
          }
        }

        guard !transcript.characters.isEmpty else {
          throw NSError(
            domain: "TranscriptService", code: 3,
            userInfo: [NSLocalizedDescriptionKey:
              "Transcription produced no content. The audio may be silent or in an unsupported format."])
        }

        let processed: AttributedString
        if isCJK {
          processed = ChinesePunctuationRestorer().restore(transcript: transcript)
        } else {
          processed = transcript
        }

        let effectiveMaxLength = maxLength ?? defaultMaxLen
        let segmenter = TranscriptSegmenter(isCJK: isCJK, maxLength: effectiveMaxLength)
        let segments = segmenter.splitTranscriptIntoSegments(transcript: processed)
        let srtContent = SRTFormatter.format(segments: segments)

        continuation.yield(TranscriptionProgress(
          progress: 1.0,
          currentTimeSeconds: audioFileDuration,
          totalDurationSeconds: audioFileDuration,
          isComplete: true,
          srtContent: srtContent
        ))
        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
    continuation.onTermination = { _ in task.cancel() }
    return stream
  }
}
