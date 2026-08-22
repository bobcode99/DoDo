//
//  PodcastInfo.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//


import Foundation
public struct PodcastInfo: Sendable, Identifiable {
  public let id: String  // This will be the rssUrl
  public let title: String
  public let podcastInfoDescription: String?
  public let episodes: [PodcastEpisodeInfo]
  public let rssUrl: String
  public let imageURL: String
  public let language: String
  /// `itunes:author`. Often a company, so treated as a weak host hint only.
  public let author: String?
  /// `<podcast:person>` credits, as JSON.
  ///
  /// A `String`, not `[PodcastPerson]`, because this struct is persisted as a
  /// SwiftData blob and SwiftData's decoder traps on `decodeIfPresent` of a
  /// custom type — it only tolerates the primitives already used above. Encoding
  /// the cast ourselves keeps the blob decodable.
  public let peopleJSON: String?

  nonisolated init() {
    self.id = ""
    self.title = ""
    self.podcastInfoDescription = nil
    self.episodes = []
    self.rssUrl = ""
    self.imageURL = ""
    self.language = ""
    self.author = nil
    self.peopleJSON = nil
  }

  nonisolated init(
    title: String, description: String?, episodes: [PodcastEpisodeInfo], rssUrl: String,
    imageURL: String, language: String,
    author: String? = nil,
    people: [PodcastPerson] = [],
    episodePeople: [String: [PodcastPerson]] = [:]
  ) {
    self.peopleJSON = PodcastPeoplePayload(show: people, episodes: episodePeople).encoded
    self.id = rssUrl  // Use RSS URL as unique ID
    self.title = title
    self.podcastInfoDescription = description
    self.episodes = episodes
    self.rssUrl = rssUrl
    self.imageURL = imageURL
    self.language = language
    self.author = author
  }
}

// MARK: - Episode Merge

extension PodcastInfo {
  /// Returns a new PodcastInfo whose episode list is the union of:
  ///   1. All episodes from `updated` (current RSS snapshot, de-duplicated)
  ///   2. Episodes from `self` that are no longer in `updated` **but** whose
  ///      `EpisodeDownloadModel` key (`"\(podcastTitle)\u{1F}\(episodeTitle)"`) is
  ///      in `preservedKeys` — meaning the user downloaded, starred, or played them.
  ///
  /// This prevents episodes from silently vanishing when a feed trims its backlog.
  func merging(updatedFrom updated: PodcastInfo, preservedKeys: Set<String>) -> PodcastInfo {
    let newRSSKeys = Set(updated.episodes.map { $0.guid ?? $0.audioURL ?? $0.title })

    let orphanedUserEpisodes = episodes.filter { ep in
      // Skip if the episode is still in the new RSS (it's already included).
      guard !newRSSKeys.contains(ep.guid ?? ep.audioURL ?? ep.title) else { return false }
      // Keep only if the user has touched it (download, star, playback).
      let modelKey = "\(updated.title)\u{1F}\(ep.title)"
      return preservedKeys.contains(modelKey)
    }

    return PodcastInfo(
      title: updated.title,
      description: updated.podcastInfoDescription,
      episodes: updated.episodes + orphanedUserEpisodes,
      rssUrl: updated.rssUrl,
      imageURL: updated.imageURL,
      language: updated.language,
      author: updated.author,
      people: updated.people,
      episodePeople: updated.episodePeople
    )
  }
}

// Explicit Codable conformance to avoid MainActor isolation issues with SwiftData
extension PodcastInfo: Codable {
  private enum CodingKeys: String, CodingKey {
    case id, title, podcastInfoDescription, episodes, rssUrl, imageURL, language
    case author, peopleJSON
  }

  public nonisolated init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(String.self, forKey: .id)
    self.title = try container.decode(String.self, forKey: .title)
    self.podcastInfoDescription = try container.decodeIfPresent(String.self, forKey: .podcastInfoDescription)
    self.episodes = try container.decode([PodcastEpisodeInfo].self, forKey: .episodes)
    self.rssUrl = try container.decode(String.self, forKey: .rssUrl)
    self.imageURL = try container.decode(String.self, forKey: .imageURL)
    self.language = try container.decode(String.self, forKey: .language)
    // decodeIfPresent throughout: blobs written before speaker context existed
    // must still decode, and an absent cast list is simply an unknown one.
    self.author = try container.decodeIfPresent(String.self, forKey: .author)
    self.peopleJSON = try container.decodeIfPresent(String.self, forKey: .peopleJSON)
  }

  public nonisolated func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encodeIfPresent(podcastInfoDescription, forKey: .podcastInfoDescription)
    try container.encode(episodes, forKey: .episodes)
    try container.encode(rssUrl, forKey: .rssUrl)
    try container.encode(imageURL, forKey: .imageURL)
    try container.encode(language, forKey: .language)
    try container.encodeIfPresent(author, forKey: .author)
    try container.encodeIfPresent(peopleJSON, forKey: .peopleJSON)
  }
}

// MARK: - People

/// Wire shape for `PodcastInfo.peopleJSON`.
public nonisolated struct PodcastPeoplePayload: Codable, Sendable {
  public var show: [PodcastPerson]
  public var episodes: [String: [PodcastPerson]]

  public init(show: [PodcastPerson], episodes: [String: [PodcastPerson]]) {
    self.show = show
    self.episodes = episodes
  }

  /// nil when there is nothing to record, so the field stays absent rather than
  /// storing an empty envelope.
  var encoded: String? {
    guard !show.isEmpty || !episodes.isEmpty,
          let data = try? JSONEncoder().encode(self)
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

nonisolated extension PodcastInfo {
  private var peoplePayload: PodcastPeoplePayload? {
    guard let peopleJSON, let data = peopleJSON.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(PodcastPeoplePayload.self, from: data)
  }

  /// Channel-level credits — the show's regular cast.
  public var people: [PodcastPerson] { peoplePayload?.show ?? [] }

  /// Episode GUID → that episode's own credits, typically guests.
  public var episodePeople: [String: [PodcastPerson]] { peoplePayload?.episodes ?? [:] }
}
