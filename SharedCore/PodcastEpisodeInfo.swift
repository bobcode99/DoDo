//
//  PodcastEpisodeInfo.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

import Foundation

public struct PodcastEpisodeInfo: Sendable, Identifiable, Hashable {
  public static func == (lhs: PodcastEpisodeInfo, rhs: PodcastEpisodeInfo) -> Bool {
    lhs.id == rhs.id
  }
  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  public let title: String
  public let podcastEpisodeDescription: String?
  public let pubDate: Date?
  public let audioURL: String?
  public let imageURL: String?
  public let duration: Int?  // Duration in seconds from itunes:duration
  public let guid: String?  // Episode GUID from RSS feed
  public let transcriptURL: String?  // URL to VTT/SRT transcript from podcast:transcript tag
  public let transcriptType: String?  // MIME type of transcript (e.g., "text/vtt", "application/srt")
  public let chaptersURL: String?  // URL to Podcasting 2.0 JSON chapters file

  /// Memberwise initializer with defaults for new fields
  public nonisolated init(
    title: String,
    podcastEpisodeDescription: String? = nil,
    pubDate: Date? = nil,
    audioURL: String? = nil,
    imageURL: String? = nil,
    duration: Int? = nil,
    guid: String? = nil,
    transcriptURL: String? = nil,
    transcriptType: String? = nil,
    chaptersURL: String? = nil
  ) {
    self.title = title
    self.podcastEpisodeDescription = podcastEpisodeDescription
    self.pubDate = pubDate
    self.audioURL = audioURL
    self.imageURL = imageURL
    self.duration = duration
    self.guid = guid
    self.transcriptURL = transcriptURL
    self.transcriptType = transcriptType
    self.chaptersURL = chaptersURL
  }

  /// Unique identifier for this episode (uses audioURL or title+pubDate combo)
  public var id: String {
    if let audioURL = audioURL {
      return audioURL
    }
    // Fallback: combine title with pubDate for uniqueness
    let dateString = pubDate?.timeIntervalSince1970.description ?? "unknown"
    return "\(title)_\(dateString)"
  }

  /// Formatted duration string (e.g., "1h 5m", "48m", "3m 20s")
  public var formattedDuration: String? {
    guard let duration = duration, duration > 0 else { return nil }

    let hours = duration / 3600
    let minutes = (duration % 3600) / 60
    let seconds = duration % 60

    if hours > 0 {
      return "\(hours)h \(minutes)m"
    } else if minutes > 0 {
      if seconds > 0 && minutes < 10 {
        return "\(minutes)m \(seconds)s"
      }
      return "\(minutes)m"
    } else {
      return "\(seconds)s"
    }
  }
}

// Explicit Codable conformance to avoid MainActor isolation issues with SwiftData
extension PodcastEpisodeInfo: Codable {
  private enum CodingKeys: String, CodingKey {
    case title, podcastEpisodeDescription, pubDate, audioURL, imageURL, duration, guid
    case transcriptURL, transcriptType, chaptersURL
  }

  public nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.title = try container.decode(String.self, forKey: .title)
    self.podcastEpisodeDescription = try container.decodeIfPresent(String.self, forKey: .podcastEpisodeDescription)
    self.pubDate = try container.decodeIfPresent(Date.self, forKey: .pubDate)
    self.audioURL = try container.decodeIfPresent(String.self, forKey: .audioURL)
    self.imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
    self.duration = try container.decodeIfPresent(Int.self, forKey: .duration)
    self.guid = try container.decodeIfPresent(String.self, forKey: .guid)
    self.transcriptURL = try container.decodeIfPresent(String.self, forKey: .transcriptURL)
    self.transcriptType = try container.decodeIfPresent(String.self, forKey: .transcriptType)
    self.chaptersURL = try container.decodeIfPresent(String.self, forKey: .chaptersURL)
  }

  public nonisolated func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(title, forKey: .title)
    try container.encodeIfPresent(podcastEpisodeDescription, forKey: .podcastEpisodeDescription)
    try container.encodeIfPresent(pubDate, forKey: .pubDate)
    try container.encodeIfPresent(audioURL, forKey: .audioURL)
    try container.encodeIfPresent(imageURL, forKey: .imageURL)
    try container.encodeIfPresent(duration, forKey: .duration)
    try container.encodeIfPresent(guid, forKey: .guid)
    try container.encodeIfPresent(transcriptURL, forKey: .transcriptURL)
    try container.encodeIfPresent(transcriptType, forKey: .transcriptType)
    try container.encodeIfPresent(chaptersURL, forKey: .chaptersURL)
  }
}
