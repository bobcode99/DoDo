//
//  WhisperTranscriptService.swift
//  PodcastAnalyzer
//
//  On-device transcription using WhisperKit (OpenAI Whisper models via CoreML).
//  Produces SRT output compatible with the existing caption pipeline.
//

import Foundation
import WhisperKit

// MARK: - Progress Update

/// Progress update emitted during Whisper transcription.
/// Mirrors the shape of `TranscriptService.TranscriptionProgress` so
/// `TranscriptManager` can consume both engines identically.
nonisolated struct TranscriptionProgressUpdate: Sendable {
    let progress: Double   // 0.0 to 1.0
    let isComplete: Bool
    let srtContent: String?       // Only set when isComplete == true
    let detectedLanguage: String? // Set after language detection step, before full transcription
}

// MARK: - WhisperTranscriptService

/// Actor-isolated service that transcribes audio files using WhisperKit.
/// Output format is SRT, matching what TranscriptService (Apple Speech) produces,
/// so the rest of the pipeline (FileStorageManager, EnhancedAudioManager) is unchanged.
actor WhisperTranscriptService {

    private let logger = Logger(subsystem: "com.podcast.analyzer", category: "WhisperTranscriptService")

    // MARK: - Model Download

    /// Downloads a Whisper model variant, reporting fractional progress via the callback.
    /// Throws on failure or cancellation.
    static func downloadModel(
        variant: WhisperModelVariant,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws {
        _ = try await WhisperKit.download(
            variant: variant.rawValue,
            downloadBase: nil,
            useBackgroundSession: false
        ) { progress in
            onProgress(progress.fractionCompleted)
        }
    }

    // MARK: - Transcription

    /// Transcribes an audio file to SRT format, streaming progress updates.
    ///
    /// - Parameters:
    ///   - inputFile: URL to a local audio/video file supported by AVFoundation.
    ///   - modelVariant: Which Whisper model to use (must already be downloaded).
    /// - Returns: An `AsyncThrowingStream` that emits `TranscriptionProgressUpdate` values.
    ///            The last emission has `isComplete == true` and carries the full SRT content.
    func audioToSRTWithProgress(
        inputFile: URL,
        modelVariant: WhisperModelVariant,
        language: String? = nil
    ) -> AsyncThrowingStream<TranscriptionProgressUpdate, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    continuation.yield(
                        TranscriptionProgressUpdate(progress: 0, isComplete: false, srtContent: nil, detectedLanguage: nil)
                    )

                    // Load the model (uses cached CoreML artefacts).
                    let whisper = try await WhisperKit(model: modelVariant.rawValue)

                    continuation.yield(
                        TranscriptionProgressUpdate(progress: 0.05, isComplete: false, srtContent: nil, detectedLanguage: nil)
                    )

                    guard !Task.isCancelled else {
                        continuation.finish(throwing: CancellationError())
                        return
                    }

                    // Extract base language code (e.g. "zh-tw" → "zh", "en-us" → "en").
                    // When no language is specified, run a fast detection pass first so we can
                    // (a) show the detected language in the UI and (b) use it as an explicit
                    // hint for transcription — prevents the English-prefill bias that causes
                    // non-English audio to be transcribed as English.
                    var resolvedWhisperLanguage: String? = language.flatMap { code in
                        code.lowercased().split(separator: "-").first.map(String.init)
                    }

                    var detectedLanguage: String? = nil
                    if resolvedWhisperLanguage == nil {
                        if let detected = try? await whisper.detectLanguage(audioPath: inputFile.path) {
                            resolvedWhisperLanguage = detected.language
                            detectedLanguage = detected.language
                            continuation.yield(
                                TranscriptionProgressUpdate(progress: 0.08, isComplete: false, srtContent: nil, detectedLanguage: detected.language)
                            )
                        }
                    }

                    guard !Task.isCancelled else {
                        continuation.finish(throwing: CancellationError())
                        return
                    }

                    let options = DecodingOptions(
                        verbose: false,
                        task: .transcribe,
                        language: resolvedWhisperLanguage,
                        usePrefillPrompt: resolvedWhisperLanguage != nil,
                        wordTimestamps: true,
                        compressionRatioThreshold: 2.4,
                        logProbThreshold: -1.0,
                        noSpeechThreshold: 0.6
                    )

                    // WhisperKit streams segment-level results via a callback.
                    var allSegments: [TranscriptionSegment] = []

                    // Estimate total windows for progress reporting.
                    // WhisperKit processes audio in 30-second windows.
                    let estimatedDuration = await Self.estimateDuration(of: inputFile)
                    let windowDuration: Double = 30.0
                    let totalWindows = max(ceil(estimatedDuration / windowDuration), 1.0)

                    var lastReportedProgress = 0.08

                    let results = try await whisper.transcribe(
                        audioPath: inputFile.path,
                        decodeOptions: options,
                        callback: { progress in
                            // Use windowId to track how many 30s windows have been processed.
                            let fraction = min(
                                0.08 + 0.87 * (Double(progress.windowId + 1) / totalWindows),
                                0.95
                            )
                            if fraction > lastReportedProgress + 0.02 {
                                lastReportedProgress = fraction
                                continuation.yield(
                                    TranscriptionProgressUpdate(
                                        progress: fraction,
                                        isComplete: false,
                                        srtContent: nil,
                                        detectedLanguage: nil
                                    )
                                )
                            }
                            return nil  // continue transcription
                        }
                    )

                    guard !Task.isCancelled else {
                        continuation.finish(throwing: CancellationError())
                        return
                    }

                    // Collect all segments from all results (WhisperKit may split long audio).
                    for result in results {
                        allSegments.append(contentsOf: result.segments)
                    }

                    let srtContent = Self.segmentsToSRT(allSegments)

                    continuation.yield(
                        TranscriptionProgressUpdate(progress: 1.0, isComplete: true, srtContent: srtContent, detectedLanguage: detectedLanguage)
                    )
                    continuation.finish()

                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - SRT Formatting

    /// Strips Whisper special tokens like `<|startoftranscript|>`, `<|en|>`, `<|0.00|>`, etc.
    private static func stripSpecialTokens(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        )
    }

    /// Converts WhisperKit segments to an SRT string.
    private static func segmentsToSRT(_ segments: [TranscriptionSegment]) -> String {
        var lines: [String] = []
        for (index, segment) in segments.enumerated() {
            let text = stripSpecialTokens(segment.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            let start = formatSRTTime(TimeInterval(segment.start))
            let end = formatSRTTime(TimeInterval(segment.end))

            lines.append("\(index + 1)")
            lines.append("\(start) --> \(end)")
            lines.append(text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Formats seconds into SRT timestamp: `HH:MM:SS,mmm`
    private static func formatSRTTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "00:00:00,000" }
        let totalMs = Int(max(0, seconds) * 1000)
        let ms = totalMs % 1000
        let s = (totalMs / 1000) % 60
        let m = (totalMs / 60_000) % 60
        let h = totalMs / 3_600_000
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    // MARK: - Duration Estimation

    /// Estimates audio duration using AVURLAsset.
    private nonisolated static func estimateDuration(of url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? seconds : 0
        } catch {
            return 0
        }
    }
}

import AVFoundation
import CoreMedia
import OSLog
