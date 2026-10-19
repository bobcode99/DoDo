//
//  DiscoveryCacheStore.swift
//  PodcastAnalyzer
//
//  On-disk cache for Home's discovery content (Popular Shows + Top Episodes per
//  region) so the tab can paint instantly on cold launch — and stay browsable
//  with no internet.
//  This is re-derivable network data, so it lives in ~/Library/Caches (the same
//  place as RSSCacheService) where the OS may evict it under storage pressure.
//
//  Payloads are tiny (≤25 podcasts / ~20 episodes per region), so reads are sub-millisecond and
//  safe to do synchronously on the main thread for an instant first paint.
//

import Foundation
import OSLog

/// Namespace for reading/writing the cached discovery lists per region.
enum DiscoveryCacheStore {
  /// A region's cached top-podcasts list plus when it was fetched from the network.
  struct CachedTopPodcasts: Codable {
    let podcasts: [AppleRSSPodcast]
    let fetchedAt: Date
  }

  private static let logger = Logger(subsystem: "com.podcast.analyzer", category: "DiscoveryCache")

  /// Cap stored rows so the on-disk payload (and the synchronous decode on launch)
  /// stays small. Popular Shows only renders the first 25 anyway.
  private static let maxStored = 25

  private static let directory: URL = {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let dir = caches.appendingPathComponent("DiscoveryCache", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }()

  private static func fileURL(_ kind: String, region: String) -> URL {
    // Region codes are short alphanumerics ("us", "tw", "jp"); sanitize defensively.
    let safe = region.lowercased().filter { $0.isLetter || $0.isNumber }
    return directory.appendingPathComponent("\(kind)-\(safe).json")
  }

  /// Persist a region's Popular Shows list with the current timestamp. Best-effort.
  static func saveTopPodcasts(_ podcasts: [AppleRSSPodcast], region: String) {
    guard !podcasts.isEmpty else { return }
    let payload = CachedTopPodcasts(podcasts: Array(podcasts.prefix(maxStored)), fetchedAt: Date())
    write(payload, to: fileURL("top", region: region))
  }

  /// Load a region's cached Popular Shows, if any. Returns the list and its age so
  /// the UI can show a freshness caption. Synchronous and cheap (tiny payload).
  static func loadTopPodcasts(region: String) -> CachedTopPodcasts? {
    guard let payload = read(CachedTopPodcasts.self, from: fileURL("top", region: region)),
          !payload.podcasts.isEmpty else { return nil }
    return payload
  }

  /// Persist a region's Top Episodes. They used to live only in a static var,
  /// so an offline cold launch showed Popular Shows but no Top Episodes.
  static func saveTrendingEpisodes(_ episodes: [ApplePodcastService.TrendingEpisode], region: String) {
    guard !episodes.isEmpty else { return }
    write(episodes, to: fileURL("trending", region: region))
  }

  static func loadTrendingEpisodes(region: String) -> [ApplePodcastService.TrendingEpisode]? {
    guard let episodes = read([ApplePodcastService.TrendingEpisode].self, from: fileURL("trending", region: region)),
          !episodes.isEmpty else { return nil }
    return episodes
  }

  private static func write(_ value: some Encodable, to url: URL) {
    do {
      try JSONEncoder().encode(value).write(to: url, options: .atomic)
    } catch {
      logger.warning("Failed to write \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      logger.warning("Failed to read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }
}
