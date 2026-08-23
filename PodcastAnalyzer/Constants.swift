import Foundation
import SwiftUI

// MARK: - Notification Names

extension Notification.Name {
  static let podcastRegionChanged = Notification.Name("podcastRegionChanged")
  /// Posted when the For You toggle changes. Home listens so switching it on
  /// fills the section straight away rather than at the next load.
  static let episodeDownloadCompleted = Notification.Name("episodeDownloadCompleted")
  /// Posted by NetworkMonitor when connectivity is restored (offline → online).
  /// Lets discovery surfaces (Home) refresh stale cached content automatically.
  static let networkDidReconnect = Notification.Name("networkDidReconnect")
}

struct Constants {

  // LocalizedStringKey, not String(localized:). These are resolved by SwiftUI
  // against the environment locale, which is where LanguageManager's in-app
  // language override lives. `String(localized:)` bypasses that entirely and
  // reads the *system* language, so on a Chinese device the tabs came out in
  // Chinese even with the app set to English — and being `static let`, the
  // value was resolved once per process, so changing the language never
  // updated it either.
  static let homeString: LocalizedStringKey = "Home"
  static let libraryString: LocalizedStringKey = "Library"
  static let analysisString: LocalizedStringKey = "Analysis"
  static let settingsString: LocalizedStringKey = "Settings"
  static let searchString: LocalizedStringKey = "Search"

  /// UserDefaults key for the first-launch onboarding flag. Shared because
  /// views read it through `@AppStorage` while the import intent and the
  /// `podcastanalyzer://import-podcasts` handler write it directly — five
  /// copies of the literal were one typo away from silently reshowing setup.
  static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

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
