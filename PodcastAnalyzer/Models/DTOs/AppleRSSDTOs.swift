//
//  AppleRSSDTOs.swift
//  PodcastAnalyzer
//
//  Decodable responses from the Apple marketing RSS API (top-podcast charts).
//

import Foundation


struct AppleRSSFeedResponse: Decodable {
    let feed: AppleRSSFeed
}

struct AppleRSSFeed: Decodable {
    let title: String?
    let country: String?
    let updated: String?
    let results: [AppleRSSPodcast]
}

struct AppleRSSPodcast: Codable, Identifiable, Hashable {
    static func == (lhs: AppleRSSPodcast, rhs: AppleRSSPodcast) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id: String
    let artistName: String
    let name: String
    let artworkUrl100: String?  // Made optional - some podcasts may not have artwork
    let url: String  // iTunes link
    let genres: [AppleRSSGenre]?
    let contentAdvisoryRating: String?
    let releaseDate: String?  // Added for robustness
    let kind: String?  // Added for robustness

    // Provide fallback for artwork URL
    var safeArtworkUrl: String {
        artworkUrl100 ?? ""
    }
}

struct AppleRSSGenre: Codable {
    let genreId: String
    let name: String
    let url: String
}
