import Foundation

// MARK: - Notification Names

extension Notification.Name {
  static let podcastRegionChanged = Notification.Name("podcastRegionChanged")
  static let episodeDownloadCompleted = Notification.Name("episodeDownloadCompleted")
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

  // Available regions for top podcasts with flag emojis
  static let podcastRegions: [(code: String, name: String, flag: String)] = [
    ("us", "United States", "🇺🇸"),
    ("tw", "Taiwan", "🇹🇼"),
    ("jp", "Japan", "🇯🇵"),
    ("gb", "United Kingdom", "🇬🇧"),
    ("au", "Australia", "🇦🇺"),
    ("ca", "Canada", "🇨🇦"),
    ("de", "Germany", "🇩🇪"),
    ("fr", "France", "🇫🇷"),
    ("kr", "South Korea", "🇰🇷"),
    ("hk", "Hong Kong", "🇭🇰"),
    ("my", "Malaysia", "🇲🇾"),
    ("in", "India", "🇮🇳"),
    ("cn", "China", "🇨🇳"),
    ("sg", "Singapore", "🇸🇬"),
    ("id", "Indonesia", "🇮🇩"),
    ("th", "Thailand", "🇹🇭"),
    ("vn", "Vietnam", "🇻🇳"),
    ("ph", "Philippines", "🇵🇭"),
    ("nz", "New Zealand", "🇳🇿"),
    ("es", "Spain", "🇪🇸"),
    ("it", "Italy", "🇮🇹"),
    ("br", "Brazil", "🇧🇷"),
    ("mx", "Mexico", "🇲🇽"),
    ("nl", "Netherlands", "🇳🇱"),
    ("se", "Sweden", "🇸🇪")
  ]
}
