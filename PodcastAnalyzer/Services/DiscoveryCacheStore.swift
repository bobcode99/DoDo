//
//  DiscoveryCacheStore.swift
//  PodcastAnalyzer
//
//  On-disk cache for Home's discovery content (Popular Shows per region) so the
//  tab can paint instantly on cold launch — and stay browsable with no internet.
//  This is re-derivable network data, so it lives in ~/Library/Caches (the same
//  place as RSSCacheService) where the OS may evict it under storage pressure.
//
//  Payloads are tiny (≤25 podcasts per region), so reads are sub-millisecond and
//  safe to do synchronously on the main thread for an instant first paint.
//

import Foundation
import OSLog

/// Namespace for reading/writing the cached Popular Shows list per region.
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

  private static func fileURL(region: String) -> URL {
    // Region codes are short alphanumerics ("us", "tw", "jp"); sanitize defensively.
    let safe = region.lowercased().filter { $0.isLetter || $0.isNumber }
    return directory.appendingPathComponent("top-\(safe).json")
  }

  /// Persist a region's Popular Shows list with the current timestamp. Best-effort.
  static func saveTopPodcasts(_ podcasts: [AppleRSSPodcast], region: String) {
    guard !podcasts.isEmpty else { return }
    let payload = CachedTopPodcasts(podcasts: Array(podcasts.prefix(maxStored)), fetchedAt: Date())
    do {
      let data = try JSONEncoder().encode(payload)
      try data.write(to: fileURL(region: region), options: .atomic)
    } catch {
      logger.warning("Failed to cache top podcasts for \(region): \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Load a region's cached Popular Shows, if any. Returns the list and its age so
  /// the UI can show a freshness caption. Synchronous and cheap (tiny payload).
  static func loadTopPodcasts(region: String) -> CachedTopPodcasts? {
    let url = fileURL(region: region)
    guard let data = try? Data(contentsOf: url) else { return nil }
    do {
      let payload = try JSONDecoder().decode(CachedTopPodcasts.self, from: data)
      return payload.podcasts.isEmpty ? nil : payload
    } catch {
      logger.warning("Failed to read cached top podcasts for \(region): \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }
}
