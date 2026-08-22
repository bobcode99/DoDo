//
//  PodcastRssService.swift
//  PodcastAnalyzer
//
//  Async/await wrapper around FeedKit with podcast namespace support.
//

import FeedKit
import Foundation
import OSLog
internal import XMLKit


public actor PodcastRssService {
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PodcastRssService")

  #if DEBUG
  private static let signpostLog = OSLog(subsystem: "com.podcast.analyzer", category: "PointsOfInterest")
  #endif

  // MARK: - Supported Transcript Types

  /// Supported transcript MIME types in order of preference
  /// Reference: https://github.com/Podcastindex-org/podcast-namespace/blob/main/docs/tags/transcript.md
  private enum TranscriptType: String, CaseIterable {
    case vtt = "text/vtt"
    case srt = "application/x-subrip"
    case srtAlt = "application/srt"

    /// Check if a MIME type matches this transcript type
    func matches(_ mimeType: String) -> Bool {
      let normalized = mimeType.lowercased().trimmingCharacters(in: .whitespaces)
      return normalized == rawValue || normalized.contains(rawValue.split(separator: "/").last ?? "")
    }

    /// Priority for selection (lower is better)
    var priority: Int {
      switch self {
      case .vtt: return 0      // Prefer VTT (most widely supported)
      case .srt: return 1      // SRT is also good
      case .srtAlt: return 1   // Same as SRT
      }
    }
  }

  /// Selected transcript info
  private struct SelectedTranscript {
    let url: String
    let type: String
    let language: String?
  }

  // MARK: - Public Methods

  /// Parses duration from iTunes duration field (FeedKit returns TimeInterval)
  private func parseDuration(_ duration: TimeInterval) -> Int {
    Int(duration)
  }

  // MARK: - Conditional HTTP Result

  /// Result of a conditional fetch. `.notModified` means the feed hasn't changed
  /// since the last fetch (HTTP 304); `.updated` carries the new content and
  /// the cache header to store for next time.
  public enum ConditionalFetchResult: Sendable {
    case notModified
    case updated(podcast: PodcastInfo, cacheHeader: String?)
  }

  /// Fetches an RSS feed with conditional HTTP support (ETag / If-Modified-Since).
  ///
  /// - Parameters:
  ///   - urlString: RSS feed URL.
  ///   - cacheHeader: The ETag or Last-Modified value stored from the previous fetch, or nil.
  /// - Returns: `.notModified` when the server returns HTTP 304; `.updated` otherwise.
  public func fetchPodcastConditional(
    from urlString: String,
    cacheHeader: String?
  ) async throws -> ConditionalFetchResult {
    guard let url = URL(string: urlString) else {
      throw PodcastServiceError.invalidURL
    }

    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData

    if let header = cacheHeader {
      // AntennaPod dual-field trick: store either ETag or Last-Modified in one field.
      // ETags start with `"` or `W/"`. Everything else is treated as a date string.
      if header.hasPrefix("\"") || header.hasPrefix("W/\"") {
        request.setValue(header, forHTTPHeaderField: "If-None-Match")
      } else {
        request.setValue(header, forHTTPHeaderField: "If-Modified-Since")
      }
    }

    let (data, response) = try await URLSession.shared.data(for: request)

    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 304 {
      return .notModified
    }

    // Extract the best cache header to store (prefer ETag, fall back to Last-Modified)
    let newCacheHeader: String? = {
      guard let http = response as? HTTPURLResponse else { return nil }
      return http.value(forHTTPHeaderField: "ETag")
        ?? http.value(forHTTPHeaderField: "Last-Modified")
    }()

    let podcast = try parseRSSPodcast(from: data, rssUrl: urlString)
    return .updated(podcast: podcast, cacheHeader: newCacheHeader)
  }

  /// Parses the given RSS URL and returns a clean model.
  /// - Parameter urlString: any RSS/Atom/JSON feed URL
  /// - Returns: `PodcastInfo` (only RSS data is kept)
  public func fetchPodcast(from urlString: String) async throws -> PodcastInfo {
    #if DEBUG
    let signpostID = OSSignpostID(log: Self.signpostLog)
    os_signpost(.begin, log: Self.signpostLog, name: "RSSService.fetchPodcast", signpostID: signpostID)
    defer { os_signpost(.end, log: Self.signpostLog, name: "RSSService.fetchPodcast", signpostID: signpostID) }
    #endif

    guard let url = URL(string: urlString) else {
      throw PodcastServiceError.invalidURL
    }

    // Fetch and parse as a dedicated RSS feed. Some podcast feeds are valid RSS but
    // can fail FeedKit's universal type detection path, so avoid that false negative.
    let (data, _) = try await URLSession.shared.data(from: url)
    return try parseRSSPodcast(from: data, rssUrl: urlString)
  }

  // MARK: - Private Helpers

  private func parseRSSPodcast(from data: Data, rssUrl: String) throws -> PodcastInfo {
    do {
      let rssFeed = try RSSFeed(data: data)
      guard let channel = rssFeed.channel else {
        throw PodcastServiceError.notRSS
      }

      logger.info("Parsed RSS feed bytes: \(data.count) from \(rssUrl, privacy: .public)")
      // FeedKit's podcast namespace covers guid and transcript only, so
      // <podcast:person> needs its own pass over the same bytes.
      let namespace = PodcastNamespaceParser().parse(from: data)
      return buildPodcastInfo(from: channel, rssUrl: rssUrl, namespace: namespace)
    } catch let error as PodcastServiceError {
      throw error
    } catch {
      logger.error("RSS parsing failed for \(rssUrl, privacy: .public): \(error.localizedDescription)")
      throw PodcastServiceError.parsingFailed(error)
    }
  }

  /// Builds a `PodcastInfo` from a parsed RSS channel.
  private func buildPodcastInfo(
    from channel: RSSFeedChannel,
    rssUrl: String,
    namespace: PodcastNamespaceData = PodcastNamespaceData(transcripts: [:], showPeople: [], episodePeople: [:])
  ) -> PodcastInfo {
    let items = channel.items ?? []
    let episodes = items.compactMap { item -> PodcastEpisodeInfo? in
      guard let title = item.title else { return nil }
      var durationSeconds: Int? = nil
      if let duration = item.iTunes?.duration {
        durationSeconds = parseDuration(duration)
      }
      let transcript = selectBestTranscript(from: item.podcast?.transcripts)
      let chaptersURL: String? = nil  // podcast:chapters not exposed by FeedKit; parsed separately if needed
      return PodcastEpisodeInfo(
        title: title,
        podcastEpisodeDescription: item.description,
        pubDate: item.pubDate,
        audioURL: item.enclosure?.attributes?.url,
        imageURL: item.iTunes?.image?.attributes?.href,
        duration: durationSeconds,
        guid: item.guid?.text,
        transcriptURL: transcript?.url,
        transcriptType: transcript?.type,
        chaptersURL: chaptersURL
      )
    }
    let transcriptCount = episodes.filter { $0.transcriptURL != nil }.count
    logger.info("Parsed \(episodes.count) episodes, \(transcriptCount) with transcripts")
    return PodcastInfo(
      title: channel.title ?? "Untitled Podcast",
      description: channel.description,
      episodes: episodes,
      rssUrl: rssUrl,
      imageURL: channel.iTunes?.image?.attributes?.href ?? "",
      language: channel.language ?? "",
      author: channel.iTunes?.author,
      people: namespace.showPeople,
      episodePeople: namespace.episodePeople
    )
  }

  /// Select the best transcript from available options
  /// Prefers VTT and SRT formats as they have timing information
  /// Reference: https://github.com/Podcastindex-org/podcast-namespace/blob/main/docs/examples/transcripts/transcripts.md
  private func selectBestTranscript(from transcripts: [PodcastTranscript]?) -> SelectedTranscript? {
    guard let transcripts = transcripts, !transcripts.isEmpty else {
      return nil
    }

    // Find supported transcripts with their priority
    var supportedTranscripts: [(transcript: SelectedTranscript, priority: Int)] = []

    for transcript in transcripts {
      guard let type = transcript.attributes?.type,
            let url = transcript.attributes?.url,
            !url.isEmpty else {
        continue
      }

      // Check if this is a supported type
      for transcriptType in TranscriptType.allCases {
        if transcriptType.matches(type) {
          let selected = SelectedTranscript(
            url: url,
            type: type,
            language: transcript.attributes?.language
          )
          supportedTranscripts.append((selected, transcriptType.priority))
          break
        }
      }
    }

    // Sort by priority (lower is better) and return the best one
    let best = supportedTranscripts.min(by: { $0.priority < $1.priority })?.transcript

    if let best = best {
      logger.debug("Selected transcript: type=\(best.type), url=\(best.url)")
    }

    return best
  }
}
