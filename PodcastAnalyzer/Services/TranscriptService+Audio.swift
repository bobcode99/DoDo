//
//  TranscriptService+Audio.swift
//  PodcastAnalyzer
//
//  Basic transcription methods: plain text, SRT, and SRT with word timings.
//

import AVFoundation
import Foundation
import OSLog
import Speech

@available(iOS 26.0, *)
extension TranscriptService {

  // MARK: - Plain text

  /// Transcribes an audio file to plain text.
  public func audioToText(inputFile: URL) async throws -> String {
    let (transcriber, analyzer) = try requireTranscriberAndAnalyzer()

    let audioURL = try await resolveAudioURL(inputFile)
    let audioFile = try AVAudioFile(forReading: audioURL)
    logger.info("Audio duration: \(Double(audioFile.length) / audioFile.processingFormat.sampleRate)s")

    try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

    var transcript: AttributedString = ""
    for try await result in transcriber.results {
      transcript += result.text
    }
    return String(transcript.characters)
  }

  // MARK: - SRT

  /// Transcribes an audio file to SRT subtitle format.
  public func audioToSRT(inputFile: URL, maxLength: Int? = nil) async throws -> String {
    let (transcriber, analyzer) = try requireTranscriberAndAnalyzer()
    try requireAudioTimeRange()

    let audioURL = try await resolveAudioURL(inputFile)
    let audioFile = try AVAudioFile(forReading: audioURL)
    logger.info("Audio duration for SRT: \(Double(audioFile.length) / audioFile.processingFormat.sampleRate)s")

    try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

    var transcript: AttributedString = ""
    for try await result in transcriber.results {
      transcript += result.text
    }

    let processed = applyCJKProcessing(to: transcript)
    let effectiveMaxLength = maxLength ?? defaultMaxLength
    let segmenter = TranscriptSegmenter(isCJK: isCJKLocale, maxLength: effectiveMaxLength)
    return SRTFormatter.format(segments: segmenter.splitTranscriptIntoSegments(transcript: processed))
  }

  // MARK: - SRT with word timings

  /// Transcribes an audio file to SRT and returns a JSON word-timing payload alongside it.
  public func audioToSRTWithWordTimings(inputFile: URL, maxLength: Int? = nil) async throws
    -> (srt: String, wordTimingsJSON: String)
  {
    let (transcriber, analyzer) = try requireTranscriberAndAnalyzer()
    try requireAudioTimeRange()

    let audioURL = try await resolveAudioURL(inputFile)
    let audioFile = try AVAudioFile(forReading: audioURL)

    try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)

    var transcript: AttributedString = ""
    for try await result in transcriber.results {
      transcript += result.text
    }

    let processed = applyCJKProcessing(to: transcript)
    let effectiveMaxLength = maxLength ?? defaultMaxLength
    let segmenter = TranscriptSegmenter(isCJK: isCJKLocale, maxLength: effectiveMaxLength)

    let segments = segmenter.extractSegmentsWithWordTimings(transcript: processed)
    let transcriptData = TranscriptData(segments: segments)

    let srtSegments = segmenter.splitTranscriptIntoSegments(transcript: processed)
    let srtContent = SRTFormatter.format(segments: srtSegments)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let jsonData = try encoder.encode(transcriptData)
    let wordTimingsJSON = String(data: jsonData, encoding: .utf8) ?? "{}"

    return (srtContent, wordTimingsJSON)
  }

  // MARK: - Internal shared helpers

  func requireTranscriberAndAnalyzer() throws -> (SpeechTranscriber, SpeechAnalyzer) {
    guard let transcriber, let analyzer else {
      throw NSError(
        domain: "TranscriptService", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Transcriber or analyzer not initialized. Call setupAndInstallAssets() first."
        ])
    }
    return (transcriber, analyzer)
  }

  func requireAudioTimeRange() throws {
    guard needsAudioTimeRange else {
      throw NSError(
        domain: "TranscriptService", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey:
            "audioTimeRange must be enabled. Initialize with needsAudioTimeRange: true."
        ])
    }
  }

  func applyCJKProcessing(to transcript: AttributedString) -> AttributedString {
    guard isCJKLocale else { return transcript }
    return ChinesePunctuationRestorer().restore(transcript: transcript)
  }
}
