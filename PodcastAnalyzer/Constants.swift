import Foundation

// MARK: - Notification Names

extension Notification.Name {
  static let podcastRegionChanged = Notification.Name("podcastRegionChanged")
  static let episodeDownloadCompleted = Notification.Name("episodeDownloadCompleted")
  /// Posted by NetworkMonitor when connectivity is restored (offline → online).
  /// Lets discovery surfaces (Home) refresh stale cached content automatically.
  static let networkDidReconnect = Notification.Name("networkDidReconnect")
}

struct Constants {

  static let homeString = "Home"
  static let libraryString = "Library"
  static let analysisString = "Analysis"
  static let settingsString = "Settings"
  static let searchString = "Search"

  static let homeIconName = "house.fill"
  static let libraryIconName = "books.vertical.fill"
  static let analysisIconName = "sparkles"
  static let settingsIconName = "gearshape.fill"
  static let searchIconName = "magnifyingglass.circle.fill"

  // Apple RSS Marketing API for top podcasts
  static let appleRSSBaseURL = "https://rss.marketingtools.apple.com/api/v2"

  /// Every Apple Podcasts storefront, verified by probing the API — see
  /// `Storefronts.swift` and `locales.md`. Was 25 hand-written entries; the
  /// real set is 174, and hand-maintaining it meant the picker silently
  /// omitted most of the world.
  static var podcastRegions: [Storefront] { Storefront.all }

  /// Region to use before the user picks one. Derived from the device's
  /// locale (Settings → General → Language & Region) — no location permission
  /// needed. Falls back to "us" if the device region isn't a live storefront.
  static var defaultRegion: String {
    let code = Locale.current.region?.identifier.lowercased() ?? "us"
    return Storefront.isKnown(code) ? code : "us"
  }
}
