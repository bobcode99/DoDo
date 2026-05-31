//
//  AutoDownloadCoordinator.swift
//  PodcastAnalyzer
//
//  Single serialized actor that owns all auto-download decisions.
//  All download paths (feed refresh, network-eligible, power-eligible) funnel here.
//

import Foundation
import SwiftData
import OSLog

// MARK: - AutoDownloadTriggerReason

enum AutoDownloadTriggerReason: CustomStringConvertible, Sendable {
  case feedRefresh
  case networkBecameEligible
  case powerBecameEligible
  case manual

  nonisolated var description: String {
    switch self {
    case .feedRefresh:            "feedRefresh"
    case .networkBecameEligible:  "networkBecameEligible"
    case .powerBecameEligible:    "powerBecameEligible"
    case .manual:                 "manual"
    }
  }
}

// MARK: - AutoDownloadCoordinator

actor AutoDownloadCoordinator {
  static let shared = AutoDownloadCoordinator()
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "AutoDownloadCoordinator")
  private var isRunning = false
  private var pendingEpisodes: [(podcastTitle: String, episodeTitle: String, audioURL: String, language: String)] = []

  private init() {}

  // MARK: - Pending Episode Management

  /// Called by BackgroundSyncManager after each sync with newly discovered episodes.
  /// Merges rather than replaces so network/power retriggers can pick up episodes
  /// from multiple syncs if the user was offline for a while.
  func updatePendingEpisodes(_ episodes: [(podcastTitle: String, episodeTitle: String, audioURL: String, language: String)]) {
    let existingKeys = Set(pendingEpisodes.map { "\($0.podcastTitle)\u{1F}\($0.episodeTitle)" })
    let fresh = episodes.filter { !existingKeys.contains("\($0.podcastTitle)\u{1F}\($0.episodeTitle)") }
    pendingEpisodes.append(contentsOf: fresh)
    logger.info("Pending auto-download pool: \(self.pendingEpisodes.count) episodes")
  }

  /// Remove an episode from the pending list after a successful download.
  func removePending(podcastTitle: String, episodeTitle: String) {
    pendingEpisodes.removeAll { $0.podcastTitle == podcastTitle && $0.episodeTitle == episodeTitle }
  }

  // MARK: - Run

  func run(reason: AutoDownloadTriggerReason) async {
    guard !isRunning else {
      logger.debug("AutoDownloadCoordinator already running, skipping \(String(describing: reason))")
      return
    }
    guard !pendingEpisodes.isEmpty else { return }

    isRunning = true
    defer { isRunning = false }
    logger.info("AutoDownloadCoordinator.run(reason: \(String(describing: reason)))")

    // Read all MainActor-isolated state in a single hop.
    let (networkOK, powerOK, container, globalEnabled, cacheLimit) =
      await MainActor.run { () -> (Bool, Bool, ModelContainer?, Bool, Int) in
        let networkMonitor = NetworkMonitor.shared
        let powerMonitor = PowerMonitor.shared
        let allowCellular = UserDefaults.standard.bool(forKey: "allowCellularAutoDownload")
        let allowBattery = UserDefaults.standard.bool(forKey: "allowAutoDownloadOnBattery")
        let cacheLimit = UserDefaults.standard.integer(forKey: "episodeCacheLimit")  // 0 = unlimited
        let globalEnabled = UserDefaults.standard.bool(forKey: "autoDownloadNewEpisodes")

        let networkOK = networkMonitor.isOnWiFiOrEthernet
          || (allowCellular && networkMonitor.isCellular)
        let powerOK = powerMonitor.autoDownloadPowerAllowed(allowOnBattery: allowBattery)

        return (networkOK, powerOK, DownloadManager.shared.modelContainer, globalEnabled, cacheLimit)
      }

    guard networkOK else {
      logger.info("Auto-download skipped: network not eligible")
      return
    }
    guard powerOK else {
      logger.info("Auto-download skipped: power not eligible")
      return
    }
    guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
      logger.info("Auto-download skipped: Low Power Mode active")
      return
    }
    guard let container else {
      logger.warning("Auto-download skipped: ModelContainer not available")
      return
    }

    // Cache budget: count currently downloaded episodes.
    let ctx = ModelContext(container)
    var downloadedCount = 0
    if cacheLimit > 0 {
      let allDownloads = (try? ctx.fetch(FetchDescriptor<EpisodeDownloadModel>())) ?? []
      downloadedCount = allDownloads.filter { $0.localAudioPath != nil }.count
    }

    var downloadedThisRun = 0
    let snapshot = pendingEpisodes  // copy actor-isolated state before awaiting

    for ep in snapshot {
      // Cache budget enforcement.
      if cacheLimit > 0 && (downloadedCount + downloadedThisRun) >= cacheLimit { break }

      let podcastTitle = ep.podcastTitle
      let episodeTitle = ep.episodeTitle

      // Look up the subscribed podcast model.
      let podDescriptor = FetchDescriptor<PodcastInfoModel>(
        predicate: #Predicate { $0.title == podcastTitle && $0.isSubscribed == true }
      )
      guard let podcast = (try? ctx.fetch(podDescriptor))?.first else { continue }

      // Resolve three-state setting.
      let setting = AutoDownloadSetting(rawValue: podcast.autoDownloadSetting) ?? .inheritGlobal
      switch setting {
      case .disabled:      continue
      case .enabled:       break
      case .inheritGlobal: if !globalEnabled { continue }
      }

      // Find the PodcastEpisodeInfo struct first so the filter can see the
      // episode's actual duration. Without this we'd always evaluate the
      // duration gate with `0` (unknown), so the user's minimum-duration
      // filter never took effect.
      guard let episode = podcast.podcastInfo.episodes.first(where: { $0.title == episodeTitle }),
            let audioURL = episode.audioURL, !audioURL.isEmpty
      else { continue }

      // Episode filter (include / exclude / minimum duration).
      guard EpisodeFilterEvaluator.shouldAutoDownload(
        episodeTitle: episodeTitle,
        durationSeconds: TimeInterval(episode.duration ?? 0),
        includeFilter: podcast.episodeFilterInclude,
        excludeFilter: podcast.episodeFilterExclude,
        minDurationSeconds: podcast.episodeFilterMinDuration
      ) else { continue }

      // Per-episode autoDownloadEnabled check.
      let epKey = "\(podcastTitle)\u{1F}\(episodeTitle)"
      let epDescriptor = FetchDescriptor<EpisodeDownloadModel>(
        predicate: #Predicate { $0.id == epKey }
      )
      if let epModel = (try? ctx.fetch(epDescriptor))?.first, !epModel.autoDownloadEnabled {
        logger.debug("Skipping \(episodeTitle): autoDownloadEnabled is false")
        continue
      }

      // Enqueue on MainActor.
      await MainActor.run {
        DownloadManager.shared.downloadEpisode(
          episode: episode,
          podcastTitle: podcastTitle,
          language: ep.language
        )
      }
      downloadedThisRun += 1
      logger.info("Auto-downloading: \(episodeTitle) (\(podcastTitle))")
    }

    logger.info("AutoDownloadCoordinator finished: \(downloadedThisRun) episodes enqueued")
  }
}
