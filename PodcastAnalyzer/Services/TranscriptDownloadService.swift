//
//  TranscriptDownloadService.swift
//  PodcastAnalyzer
//
//  Downloads and converts transcript files from RSS feeds
//

import Foundation
import OSLog

// MARK: - Download State

/// State of transcript download for an episode
public enum TranscriptDownloadState: Equatable, Sendable {
  case notAvailable
  case available(url: String, type: String)
  case downloading(progress: Double)
  case downloaded
  case failed(error: String)

  public var isAvailable: Bool {
    if case .available = self { return true }
    return false
  }

  public var isDownloading: Bool {
    if case .downloading = self { return true }
    return false
  }

  public var isDownloaded: Bool {
    if case .downloaded = self { return true }
    return false
  }
}

// MARK: - Transcript Download Service

/// Service for downloading and converting transcript files from RSS feeds
public actor TranscriptDownloadService {

  public static let shared = TranscriptDownloadService()

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "TranscriptDownloadService")

  // Track active downloads
  private var activeDownloads: Set<String> = []

  private init() {}

  // MARK: - Public Methods

  /// Download transcript from URL, convert to SRT if needed, and store it.
  /// - Parameters:
  ///   - url: URL to the transcript file
  ///   - type: MIME type of the transcript (text/vtt, application/srt, etc.)
  ///   - episodeTitle: Episode title
  ///   - podcastTitle: Podcast title
  public func downloadTranscript(
    from url: URL,
    type: String,
    episodeTitle: String,
    podcastTitle: String
  ) async throws {
    let downloadKey = makeDownloadKey(podcastTitle: podcastTitle, episodeTitle: episodeTitle)

    // Check if already downloading
    guard !activeDownloads.contains(downloadKey) else {
      throw TranscriptDownloadError.alreadyDownloading
    }

    activeDownloads.insert(downloadKey)
    defer { activeDownloads.remove(downloadKey) }

    logger.info("Starting transcript download: \(url.absoluteString)")

    // 1. Download the file
    let (data, response) = try await URLSession.shared.data(from: url)

    // Check response status
    if let httpResponse = response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    {
      logger.error("Transcript download failed with status: \(httpResponse.statusCode)")
      throw TranscriptDownloadError.downloadFailed(statusCode: httpResponse.statusCode)
    }

    guard let content = String(data: data, encoding: .utf8) else {
      throw TranscriptDownloadError.invalidContent
    }

    logger.debug("Downloaded transcript: \(data.count) bytes")

    // 2. Detect format and convert to SRT if needed
    let srtContent: String
    if isVTTContent(content, mimeType: type) {
      logger.debug("Converting VTT to SRT")
      srtContent = VTTParser.convertToSRT(content)
    } else if isSRTContent(content, mimeType: type) {
      srtContent = content
    } else if isPlainTextContent(content, mimeType: type) {
      // Plain text - create simple SRT with no timing
      srtContent = convertPlainTextToSRT(content)
    } else {
      // Try to parse as VTT first, then SRT
      if VTTParser.isVTTContent(content) {
        srtContent = VTTParser.convertToSRT(content)
      } else {
        // Assume it's SRT or compatible
        srtContent = content
      }
    }

    // 3. Save to structured storage (parsed once here, not re-parsed on every load)
    // `_ =`: saveTranscript is @discardableResult, but that doesn't propagate
    // through MainActor.run's generic return value.
    _ = try await MainActor.run {
      try TranscriptStore.shared.saveTranscript(
        srtContent: srtContent,
        episodeTitle: episodeTitle,
        podcastTitle: podcastTitle,
        source: "rss"
      )
    }

    logger.info("Saved RSS transcript for: \(episodeTitle)")
  }

  /// Check if a local transcript exists for an episode
  public func hasLocalTranscript(episodeTitle: String, podcastTitle: String) async -> Bool {
    await MainActor.run {
      TranscriptStore.shared.exists(episodeTitle: episodeTitle, podcastTitle: podcastTitle)
    }
  }

  /// Get the download state for an episode
  public func getDownloadState(
    episodeTitle: String,
    podcastTitle: String,
    transcriptURL: String?,
    transcriptType: String?
  ) async -> TranscriptDownloadState {
    // Check if already downloaded
    if await hasLocalTranscript(episodeTitle: episodeTitle, podcastTitle: podcastTitle) {
      return .downloaded
    }

    // Check if currently downloading
    let downloadKey = makeDownloadKey(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
    if activeDownloads.contains(downloadKey) {
      return .downloading(progress: 0.5)  // We don't have granular progress
    }

    // Check if transcript URL is available
    if let url = transcriptURL, let type = transcriptType {
      return .available(url: url, type: type)
    }

    return .notAvailable
  }

  /// Delete downloaded transcript
  public func deleteTranscript(episodeTitle: String, podcastTitle: String) async throws {
    try await MainActor.run {
      try TranscriptStore.shared.delete(episodeTitle: episodeTitle, podcastTitle: podcastTitle)
    }
    logger.info("Deleted transcript for: \(podcastTitle) - \(episodeTitle)")
  }

  // MARK: - Private Helpers

  private func makeDownloadKey(podcastTitle: String, episodeTitle: String) -> String {
    "\(podcastTitle)\u{1F}\(episodeTitle)"
  }

  private func isVTTContent(_ content: String, mimeType: String) -> Bool {
    let typeLC = mimeType.lowercased()
    return typeLC.contains("vtt") || content.trimmingCharacters(in: .whitespacesAndNewlines)
      .hasPrefix("WEBVTT")
  }

  private func isSRTContent(_ content: String, mimeType: String) -> Bool {
    let typeLC = mimeType.lowercased()
    return typeLC.contains("srt") || typeLC == "application/x-subrip"
  }

  private func isPlainTextContent(_ content: String, mimeType: String) -> Bool {
    let typeLC = mimeType.lowercased()
    return typeLC == "text/plain"
  }

  /// Convert plain text transcript to simple SRT format
  /// Creates segments based on sentence boundaries
  private func convertPlainTextToSRT(_ text: String) -> String {
    // Split into sentences
    let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    var srtContent = ""
    var segmentIndex = 1

    // Create segments with estimated timing (5 seconds per segment)
    for (index, sentence) in sentences.enumerated() {
      let startTime = TimeInterval(index * 5)
      let endTime = TimeInterval((index + 1) * 5)

      srtContent += "\(segmentIndex)\n"
      srtContent += "\(formatSRTTime(startTime)) --> \(formatSRTTime(endTime))\n"
      srtContent += "\(sentence).\n"
      srtContent += "\n"

      segmentIndex += 1
    }

    return srtContent
  }

  private func formatSRTTime(_ time: TimeInterval) -> String {
    let hours = Int(time) / 3600
    let minutes = (Int(time) % 3600) / 60
    let seconds = Int(time) % 60
    let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
    return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
  }
}

// MARK: - Errors

public enum TranscriptDownloadError: LocalizedError {
  case alreadyDownloading
  case downloadFailed(statusCode: Int)
  case invalidContent
  case conversionFailed
  case saveFailed(Error)

  public var errorDescription: String? {
    switch self {
    case .alreadyDownloading:
      return "Transcript download is already in progress"
    case .downloadFailed(let statusCode):
      return "Download failed with status code: \(statusCode)"
    case .invalidContent:
      return "Invalid transcript content"
    case .conversionFailed:
      return "Failed to convert transcript format"
    case .saveFailed(let error):
      return "Failed to save transcript: \(error.localizedDescription)"
    }
  }
}
