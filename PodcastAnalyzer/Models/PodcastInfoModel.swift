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
  ///
  /// didSet pushes to iCloud (SubscriptionSyncCoordinator) here rather than
  /// at each call site: subscribe/unsubscribe is toggled directly on this
  /// property from ~8 places (PodcastSubscriptionViewModel, HomeViewModel,
  /// SearchView, EpisodeListView, PodcastContextMenu). Centralizing means
  /// Mutate through `setSubscribed(_:)`, never directly: SwiftData quietly
  /// ignores property observers on managed @Model instances, so a `didSet`
  /// here never fires for fetched models and subscribe/unsubscribe changes
  /// silently skip iCloud. Call sites that construct an already-subscribed
  /// model (import, silent resubscribe) call
  /// `SubscriptionSyncCoordinator.sync(from:)` explicitly after insert.
  var isSubscribed: Bool = false

  /// The single funnel for subscribe/unsubscribe on an existing model —
  /// flips the flag and mirrors the change to the CloudKit store.
  @MainActor
  func setSubscribed(_ subscribed: Bool) {
    guard subscribed != isSubscribed else { return }
    isSubscribed = subscribed
    SubscriptionSyncCoordinator.shared.sync(from: self)
  }

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

  /// Per-podcast transcription vocabulary: proper nouns / jargon (host & guest
  /// names, companies, terms) applied to the SpeechAnalyzer as contextual
  /// strings so on-device transcription spells them correctly. User-edited and
  /// not derived from the RSS feed — it lives on the row, so it survives a feed
  /// rename (unlike a title-keyed store). Distinct from the AI "Show Format".
  var transcriptionTerms: [String] = []

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
