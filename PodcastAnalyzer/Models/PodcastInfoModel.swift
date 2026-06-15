import Foundation
import SwiftData

// MARK: - AutoDownloadSetting

enum AutoDownloadSetting: String, CaseIterable {
  case enabled       = "enabled"
  case disabled      = "disabled"
  case inheritGlobal = "inheritGlobal"

  var displayName: String {
    switch self {
    case .enabled:       "Always"
    case .disabled:      "Never"
    case .inheritGlobal: "Use Global Setting"
    }
  }
}

@Model
class PodcastInfoModel {
  // Indexes for the hot query paths: the subscribed-podcasts @Query, identity
  // lookups by rssUrl/title, and recency sorting.
  #Index<PodcastInfoModel>([\.isSubscribed], [\.rssUrl], [\.title], [\.lastUpdated])

  var id: UUID = UUID()

  var podcastInfo: PodcastInfo = PodcastInfo()

  var dateAdded: Date = Date()
  var lastUpdated: Date = Date()

  /// Whether the user has subscribed to this podcast.
  /// false = browsed/cached podcast, true = subscribed podcast
  var isSubscribed: Bool = false

  // MARK: - Queryable Properties (Swift 6 Predicate Compatibility)
  // These top-level properties enable #Predicate to work without nested keypaths
  // which don't conform to Sendable in Swift 6 strict concurrency mode

  /// Podcast title for predicate queries (mirrors podcastInfo.title)
  var title: String = ""

  /// RSS URL for predicate queries (mirrors podcastInfo.rssUrl)
  var rssUrl: String = ""

  // MARK: - Denormalized grid fields
  // Mirror the handful of podcast-level values the Library grid renders +
  // sorts on, so the grid never has to decode the full `podcastInfo` episode
  // blob just to draw artwork and a date. Kept in sync by `applyPodcastInfo`
  // / init; legacy rows are backfilled by LibraryViewModel.loadAllPodcasts.

  /// Podcast artwork URL (mirrors podcastInfo.imageURL).
  var imageURL: String = ""
  /// Number of episodes in the current snapshot (mirrors podcastInfo.episodes.count).
  var episodeCount: Int = 0
  /// Newest episode pubDate in the snapshot — drives the grid's recency sort.
  var latestEpisodeDate: Date?

  /// Stores either an ETag token or a Last-Modified date string from the last
  /// successful RSS fetch (AntennaPod dual-field trick). nil = never fetched.
  var httpCacheHeader: String?

  /// Predicted date of the next new episode based on release cadence analysis.
  /// nil = not yet analysed or cadence is irregular.
  var predictedNextReleaseDate: Date?

  /// Human-readable cadence detected by ReleaseScheduleGuesser (e.g. "weekly").
  var detectedCadence: String?

  // MARK: - Per-Podcast Automation

  /// When `true`, new episodes from this podcast are queued for transcription
  /// automatically. The engine is resolved at execution time: YAP server when
  /// configured, otherwise a local engine (Whisper / Apple Speech) gated by the
  /// device's charging state. Respects `TranscriptManager`'s per-podcast
  /// session failure cap.
  var autoTranscribeNewEpisodes: Bool = false

  /// Three-state auto-download setting (AntennaPod pattern).
  /// "enabled" | "disabled" | "inheritGlobal".
  var autoDownloadSetting: String = AutoDownloadSetting.inheritGlobal.rawValue

  /// Comma-separated include terms (case-insensitive). Empty = no filter.
  var episodeFilterInclude: String = ""
  /// Comma-separated exclude terms (case-insensitive). Empty = no filter.
  var episodeFilterExclude: String = ""
  /// Minimum episode duration in seconds; 0 = no minimum.
  var episodeFilterMinDuration: Int = 0

  init(podcastInfo: PodcastInfo, lastUpdated: Date, isSubscribed: Bool = true) {
    self.id = UUID()
    self.podcastInfo = podcastInfo
    self.dateAdded = Date()
    self.lastUpdated = lastUpdated
    self.isSubscribed = isSubscribed
    // Initialize queryable properties
    self.title = podcastInfo.title
    self.rssUrl = podcastInfo.rssUrl
    // Initialize denormalized grid mirrors
    self.imageURL = podcastInfo.imageURL
    self.episodeCount = podcastInfo.episodes.count
    self.latestEpisodeDate = podcastInfo.episodes.lazy.compactMap(\.pubDate).max()
  }

  /// The single funnel for replacing the stored podcast snapshot. SwiftData
  /// silently ignores property observers on `@Model`, so assigning
  /// `podcastInfo` directly leaves the denormalized `title`/`rssUrl` mirrors
  /// stale — which then breaks every `#Predicate { $0.title == … }` /
  /// `{ $0.rssUrl == … }` lookup after a feed renames (downloads, AI analysis,
  /// and queue items keyed by the old title silently orphan). Always assign
  /// the podcast snapshot through here so the query mirrors stay in sync.
  func applyPodcastInfo(_ info: PodcastInfo) {
    self.podcastInfo = info
    self.title = info.title
    self.rssUrl = info.rssUrl
    self.imageURL = info.imageURL
    self.episodeCount = info.episodes.count
    self.latestEpisodeDate = info.episodes.lazy.compactMap(\.pubDate).max()
  }
}
