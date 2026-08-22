import Foundation
import OSLog

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "ApplePodcastService")

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
    var id: UUID { UUID() }  // ← computed, no warning
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
    var id: UUID { UUID() }  // ← computed, no warning
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
// MARK: - Apple RSS Top Podcasts Response Models

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

// MARK: - Apple Podcast Service (Swift 6 async/await)

class ApplePodcastService: Sendable {

    private let baseURL = "https://itunes.apple.com"
    private let rssBaseURL = Constants.appleRSSBaseURL

    // MARK: - Top Podcasts from Apple RSS Marketing API

    /// Fetches top podcasts for a given region
    /// - Parameters:
    ///   - region: Country code (e.g., "us", "tw", "jp")
    ///   - limit: Number of podcasts to fetch (max 200)
    /// - Returns: Array of top podcasts
    func fetchTopPodcasts(region: String = "us", limit: Int = 10) async throws -> [AppleRSSPodcast] {
        let urlString = "\(rssBaseURL)/\(region)/podcasts/top/\(limit)/podcasts.json"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        // Check HTTP status code
        if let httpResponse = response as? HTTPURLResponse {
            logger.debug("Apple RSS API response status: \(httpResponse.statusCode) for region: \(region)")
            guard (200...299).contains(httpResponse.statusCode) else {
                logger.error("Apple RSS API returned status \(httpResponse.statusCode)")
                throw URLError(.badServerResponse)
            }
        }

        // Try standard decoding first
        do {
            let decoder = JSONDecoder()
            let feedResponse = try decoder.decode(AppleRSSFeedResponse.self, from: data)
            logger.info("Successfully decoded \(feedResponse.feed.results.count) podcasts for region: \(region)")
            return feedResponse.feed.results
        } catch let decodingError as DecodingError {
            // Log detailed decoding error for debugging
            logger.error("Decoding error for region \(region): \(decodingError.localizedDescription)")

            // Try manual parsing as fallback to handle malformed items
            return try parseTopPodcastsManually(from: data, region: region)
        }
    }

    // MARK: - Storefront Availability

    /// Whether Apple serves podcast charts for this storefront.
    ///
    /// The API answers 200 for a live storefront and 500 for a code that isn't
    /// one, which is the whole test — there is no discovery endpoint listing
    /// them. `locales.md` was generated by running exactly this over every
    /// ISO 3166-1 alpha-2 code.
    ///
    /// Returns false rather than throwing: to the user "we couldn't confirm
    /// this works" and "this doesn't exist" lead to the same next step, and a
    /// thrown error would only make the caller restate that.
    func probeStorefront(_ code: String) async -> Bool {
        let code = code.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty,
              let url = URL(string: "\(rssBaseURL)/\(code)/podcasts/top/1/podcast-episodes.json")
        else { return false }

        var request = URLRequest(url: url)
        // Short: this sits behind a button the user is waiting on, and the
        // answer is a status code that arrives with the headers.
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            logger.info("Storefront probe \(code, privacy: .public) -> \(status)")
            return (200...299).contains(status)
        } catch {
            logger.error("Storefront probe \(code, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Manual parsing fallback that skips malformed podcast entries
    private func parseTopPodcastsManually(from data: Data, region: String) throws -> [AppleRSSPodcast] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let feed = json["feed"] as? [String: Any],
              let results = feed["results"] as? [[String: Any]] else {
            logger.error("Failed to parse JSON structure for region: \(region)")
            throw URLError(.cannotParseResponse)
        }

        var podcasts: [AppleRSSPodcast] = []
        let decoder = JSONDecoder()

        for (index, item) in results.enumerated() {
            do {
                let itemData = try JSONSerialization.data(withJSONObject: item)
                let podcast = try decoder.decode(AppleRSSPodcast.self, from: itemData)
                podcasts.append(podcast)
            } catch {
                // Log and skip malformed items instead of failing completely
                let name = item["name"] as? String ?? "unknown"
                logger.warning("Skipping malformed podcast at index \(index) (\(name)): \(error.localizedDescription, privacy: .public)")
            }
        }

        logger.info("Manual parsing recovered \(podcasts.count) of \(results.count) podcasts for region: \(region)")
        return podcasts
    }

    /// Looks up a podcast's RSS feed URL from its collection ID
    func lookupPodcast(collectionId: String) async throws -> Podcast? {
        let urlString = "\(baseURL)/lookup?id=\(collectionId)&entity=podcast"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.results.first
    }

    /// Finds the Apple Podcasts episode link by matching the episode GUID
    /// - Parameters:
    ///   - episodeTitle: Episode title for search query
    ///   - episodeGuid: The RSS feed GUID to match against Apple's episodeGuid
    ///   - country: Country code for the search (default: "tw")
    /// - Returns: The Apple episode URL or nil
    func getAppleEpisodeLink(
        episodeTitle: String,
        episodeGuid: String?,
        country: String = "tw"
    ) async throws -> String? {
        let encoded = episodeTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://itunes.apple.com/search?term=\(encoded)&entity=podcastEpisode&limit=15&country=\(country)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(EpisodeSearchResponse.self, from: data)

        // Priority 1: Match by episodeGuid
        if let guid = episodeGuid,
           let match = response.results.first(where: { $0.episodeGuid == guid }) {
            return match.trackViewUrl
        }
        // Fallback: return first result
        return response.results.first?.trackViewUrl
    }

    // MARK: - Trending Episodes

    /// A trending episode with podcast context
    struct TrendingEpisode: Identifiable, Sendable {
        let id: String  // collectionId + episodeTitle
        let podcastName: String
        let podcastArtworkUrl: String?
        let podcastId: String
        let episode: Episode

        /// Convert to AppleRSSPodcast for navigation reuse
        var asAppleRSSPodcast: AppleRSSPodcast {
            AppleRSSPodcast(
                id: podcastId,
                artistName: podcastName,
                name: podcastName,
                artworkUrl100: podcastArtworkUrl,
                url: episode.trackViewUrl ?? "",
                genres: nil,
                contentAdvisoryRating: nil,
                releaseDate: nil,
                kind: nil
            )
        }
    }

    /// Lightweight trending episodes fetch using iTunes Lookup API (no RSS parsing).
    /// Much faster than the old RSS approach — single JSON call per podcast.
    /// - Parameters:
    ///   - topPodcasts: Already-fetched top podcasts to reuse
    ///   - episodesPerPodcast: Number of latest episodes per podcast (default 2)
    /// - Returns: Array of trending episodes sorted by release date
    func fetchTrendingEpisodesFromLookup(
        topPodcasts: [AppleRSSPodcast],
        episodesPerPodcast: Int = 2
    ) async throws -> [TrendingEpisode] {
        var allTrending: [TrendingEpisode] = []

        await withTaskGroup(of: [TrendingEpisode].self) { group in
            for podcast in topPodcasts {
                group.addTask {
                    do {
                        let episodes = try await self.fetchEpisodes(
                            for: Int(podcast.id) ?? 0,
                            limit: episodesPerPodcast
                        )
                        return episodes.map { episode in
                            TrendingEpisode(
                                id: "\(podcast.id)_\(episode.trackName)",
                                podcastName: podcast.name,
                                podcastArtworkUrl: podcast.artworkUrl100,
                                podcastId: podcast.id,
                                episode: episode
                            )
                        }
                    } catch {
                        return []
                    }
                }
            }

            for await episodes in group {
                allTrending.append(contentsOf: episodes)
            }
        }

        // Sort by release date (newest first)
        return allTrending.sorted { e1, e2 in
            (e1.episode.releaseDate ?? "") > (e2.episode.releaseDate ?? "")
        }
    }

    // Search podcasts
    func searchPodcasts(term: String, limit: Int = 20) async throws -> [Podcast] {
        let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString =
            "\(baseURL)/search?media=podcast&entity=podcast&term=\(encoded)&limit=\(limit)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return response.results
    }

    // Fetch episodes from Apple (fixed to handle only podcast return without error)
    func fetchEpisodes(for collectionId: Int, limit: Int = 200) async throws -> [Episode] {
        let urlString = "\(baseURL)/lookup?id=\(collectionId)&entity=podcastEpisode&limit=\(limit)"

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        // Parse as dict first (like ObjectMapper in Java to avoid direct decode errors)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        guard let results = json?["results"] as? [[String: Any]] else {
            throw URLError(.badServerResponse)
        }

        var episodes: [Episode] = []
        for item in results.dropFirst() {  // Skip first (podcast); like filtering in a Java stream
            let itemData = try JSONSerialization.data(withJSONObject: item, options: [])
            let episode = try JSONDecoder().decode(Episode.self, from: itemData)
            episodes.append(episode)
        }
        return episodes
    }

    // Fetch episodes from RSS feed (alternative since Apple doesn't return them)
    func fetchEpisodesFromRSS(feedUrl: String, limit: Int = 200) async throws -> [Episode] {
        guard let url = URL(string: feedUrl) else {
            throw URLError(.badURL)
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let parser = RSSParser(data: data)
        let episodes = try parser.parse()
        return Array(episodes.prefix(limit))
    }
}

// MARK: - RSS Parser class (like a custom XML parser service in Java)

class RSSParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var episodes: [Episode] = []

    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentDuration = ""
    private var currentEnclosureUrl = ""
    private var currentGuid = ""
    private var language = ""  // From channel <language>

    init(data: Data) {
        self.data = data
    }

    func parse() throws -> [Episode] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        if parser.parse() {
            return episodes
        } else if let error = parser.parserError {
            throw error
        } else {
            throw URLError(.cannotParseResponse)
        }
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "item" {
            currentTitle = ""
            currentDescription = ""
            currentPubDate = ""
            currentDuration = ""
            currentEnclosureUrl = ""
            currentGuid = ""
        } else if elementName == "enclosure" {
            currentEnclosureUrl = attributeDict["url"] ?? ""
        } else if elementName == "itunes:duration" {
            currentDuration = ""
        } else if elementName == "language" {
            language = ""
        } else if elementName == "guid" {
            currentGuid = ""
        } else if elementName == "description" {
            currentDescription = ""
        }  // Add more for other fields if needed
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }

        switch currentElement {
        case "title": currentTitle += trimmed
        case "description": currentDescription += trimmed
        case "pubDate": currentPubDate += trimmed
        case "itunes:duration": currentDuration += trimmed
        case "guid": currentGuid += trimmed
        case "language": language += trimmed
        default: break
        }
    }

    func parser(
        _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "item" {
            // Parse duration to millis (like string parsing in Java)
            var millis: Int? = nil
            if !currentDuration.isEmpty {
                if let sec = Int(currentDuration) {
                    millis = sec * 1000
                } else {
                    let parts = currentDuration.split(separator: ":")
                    if parts.count == 3, let h = Int(parts[0]), let m = Int(parts[1]),
                        let s = Int(parts[2])
                    {
                        millis = (h * 3600 + m * 60 + s) * 1000
                    } else if parts.count == 2, let m = Int(parts[0]), let s = Int(parts[1]) {
                        millis = (m * 60 + s) * 1000
                    }
                }
            }

            let episode = Episode(
                wrapperType: "podcastEpisode",
                kind: "podcast-episode",
                trackId: nil,  // No Apple ID
                trackName: currentTitle,
                description: currentDescription,
                shortDescription: nil,
                releaseDate: currentPubDate,
                trackTimeMillis: millis,
                contentAdvisoryRating: nil,
                trackViewUrl: nil,  // No Apple link available from RSS
                previewUrl: nil,
                episodeUrl: currentEnclosureUrl,
                artworkUrl600: nil,
                artworkUrl160: nil,
                country: nil,
                language: language,  // From RSS
                genres: nil,
                collectionId: nil,
                collectionName: nil,
                episodeGuid: currentGuid,
                closedCaptioning: nil,
                episodeContentType: nil,
                episodeFileExtension: nil
            )
            episodes.append(episode)
        }
    }
}
