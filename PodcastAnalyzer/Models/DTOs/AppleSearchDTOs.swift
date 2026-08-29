//
//  AppleSearchDTOs.swift
//  PodcastAnalyzer
//
//  Decodable responses from the iTunes Search API (itunes.apple.com/search|lookup).
//

import Foundation

struct SearchResponse: Decodable {
    let resultCount: Int
    let results: [Podcast]
}

struct EpisodeSearchResponse: Decodable {
    let resultCount: Int
    let results: [Episode]
}
// Podcast struct - unchanged, from search with direct fields
struct Podcast: Decodable, Identifiable, Sendable {
    /// Apple's own collection id. Must be stable across accesses — a fresh
    /// UUID per read silently breaks ForEach diffing and matched transitions.
    var id: Int { collectionId }
    let collectionId: Int  // Like @Id in JPA
    let collectionName: String
    let artistName: String
    let artworkUrl100: String?  // Optional, like String in Java (nullable)
    let feedUrl: String?  // RSS feed URL
    let contentAdvisoryRating: String?  // e.g., "Explicit"
    let genres: [String]?  // Like List<String> in Java
}
/// Genre object from Apple API
struct EpisodeGenre: Decodable, Sendable {
    let name: String
    let id: String
}

struct Episode: Decodable, Identifiable, Sendable {
    /// Stable across accesses, in the order Apple actually populates: the
    /// numeric track id from search, the guid from RSS, the title as a
    /// last resort. Never a fresh UUID — that breaks ForEach diffing.
    var id: String {
        if let trackId { return String(trackId) }
        return episodeGuid ?? trackName
    }
    let wrapperType: String?
    let kind: String?

    let trackId: Int?  // Optional now; nil from RSS
    let trackName: String
    let description: String?
    let shortDescription: String?

    let releaseDate: String?
    let trackTimeMillis: Int?

    let contentAdvisoryRating: String?

    let trackViewUrl: String?  // Apple episode link
    let previewUrl: String?
    let episodeUrl: String?  // Audio URL

    let artworkUrl600: String?
    let artworkUrl160: String?

    let country: String?
    let language: String?

    let genres: [EpisodeGenre]?  // Fixed: Array of genre objects, not strings

    let collectionId: Int?
    let collectionName: String?

    let episodeGuid: String?
    let closedCaptioning: String?
    let episodeContentType: String?
    let episodeFileExtension: String?
}
