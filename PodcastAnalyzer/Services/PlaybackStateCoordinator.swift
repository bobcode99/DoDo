//
//  PlaybackStateCoordinator.swift
//  PodcastAnalyzer
//
//  Coordinates playback position updates between EnhancedAudioManager and SwiftData
//

import Foundation
import SwiftData
import OSLog

@MainActor
@Observable
class PlaybackStateCoordinator {
  static var shared: PlaybackStateCoordinator?

  // Use Unit Separator (U+001F) as delimiter - same as DownloadManager for consistency
  private static let episodeKeyDelimiter = "\u{1F}"

  private var modelContext: ModelContext?
  private var notificationTask: Task<Void, Never>?
  private let logger = Logger(
    subsystem: "com.podcast.analyzer", category: "PlaybackStateCoordinator")

  // Helper to create episode ID matching episode key format
  private func makeEpisodeId(podcastTitle: String, episodeTitle: String) -> String {
    return "\(podcastTitle)\(Self.episodeKeyDelimiter)\(episodeTitle)"
  }

  init(modelContext: ModelContext) {
    self.modelContext = modelContext
    setupNotificationObserver()
    Self.shared = self  // Keep singleton reference
  }

  private func setupNotificationObserver() {
    notificationTask = Task { [weak self] in
      for await notification in NotificationCenter.default.notifications(named: .playbackPositionDidUpdate) {
        guard let update = notification.userInfo?["update"] as? PlaybackPositionUpdate else { continue }
        self?.savePlaybackPosition(update: update)
      }
    }

    logger.info("Playback state coordinator initialized")
  }

  // No deinit — singleton lives for app lifetime. Task cancelled via notification observer lifecycle.

  /// Look up the saved playback position for an episode from SwiftData.
  /// Returns 0 if no saved position or if the episode is already completed.
  static func savedPlaybackPosition(podcastTitle: String, episodeTitle: String) -> TimeInterval {
    guard let coordinator = shared, let context = coordinator.modelContext else { return 0 }
    let id = coordinator.makeEpisodeId(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == id }
    )
    guard let model = try? context.fetch(descriptor).first else { return 0 }
    // Don't resume completed episodes - start from beginning
    if model.isCompleted { return 0 }
    return model.lastPlaybackPosition
  }

  // MARK: - Queue Persistence

  func saveQueue(_ queue: [PlaybackEpisode]) {
    guard let context = modelContext else { return }

    // Delete all existing queue items
    do {
      try context.delete(model: QueueItemModel.self)
    } catch {
      logger.error("Failed to delete old queue items: \(error.localizedDescription, privacy: .public)")
    }

    // Insert new items with position indices
    for (index, episode) in queue.enumerated() {
      let item = QueueItemModel(from: episode, position: index)
      context.insert(item)
    }

    do {
      try context.save()
      logger.debug("Saved \(queue.count) queue items")
    } catch {
      logger.error("Failed to save queue: \(error.localizedDescription, privacy: .public)")
    }
  }

  func restoreQueue() -> [PlaybackEpisode] {
    guard let context = modelContext else { return [] }

    var descriptor = FetchDescriptor<QueueItemModel>(
      sortBy: [SortDescriptor(\.position)]
    )
    descriptor.fetchLimit = 50

    do {
      let items = try context.fetch(descriptor)
      let episodes = items.map { $0.toPlaybackEpisode() }
      logger.info("Restored \(episodes.count) queue items")
      return episodes
    } catch {
      logger.error("Failed to restore queue: \(error.localizedDescription, privacy: .public)")
      return []
    }
  }

  /// Internal (not private) so tests can drive the persistence step directly
  /// instead of posting `.playbackPositionDidUpdate`, which every live
  /// coordinator in the process — including the host app's, backed by the real
  /// store — would also act on.
  func savePlaybackPosition(update: PlaybackPositionUpdate) {
    guard let context = modelContext else { return }

    let id = makeEpisodeId(podcastTitle: update.podcastTitle, episodeTitle: update.episodeTitle)
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == id }
    )

    do {
      let results = try context.fetch(descriptor)

      let model: EpisodeDownloadModel
      if let existingModel = results.first {
        // Update existing model
        model = existingModel
        logger.debug("Updating existing episode model: \(update.episodeTitle)")
      } else {
        // Create new model automatically
        logger.info("Creating new episode model for: \(update.episodeTitle)")
        model = EpisodeDownloadModel(
          episodeTitle: update.episodeTitle,
          podcastTitle: update.podcastTitle,
          audioURL: update.audioURL
        )
        context.insert(model)
      }

      // Update playback state
      model.lastPlaybackPosition = update.position
      model.lastPlayedDate = Date()
      model.progressUpdatedAt = Date()

      // IMPORTANT: Always update duration from the player (this is the actual duration)
      if update.duration > 0 {
        model.duration = update.duration
      }

      // Reset completed status when replaying (position is before 90% of duration)
      // This allows users to re-listen and get fresh progress tracking
      if model.isCompleted && update.duration > 0 {
        let progressRatio = update.position / update.duration
        if progressRatio < 0.9 {
          model.setCompleted(false)
          logger.info(
            "Reset completed status for: \(update.episodeTitle) (replay detected at \(Int(progressRatio * 100))%)"
          )
        }
      }

      // Mark as completed if within 30 seconds of end
      let wasCompleted = model.isCompleted
      if update.duration > 0 && (update.duration - update.position) < 30 {
        model.setCompleted(true)
      }

      // Notify when completion state changes so UI (e.g. Up Next) can refresh
      if model.isCompleted != wasCompleted {
        if model.isCompleted {
          model.playCount += 1
        }
        NotificationCenter.default.post(name: .episodeCompletionChanged, object: nil)
      }

      try context.save()
      logger.info(
        "✅ Saved playback: \(update.episodeTitle) at \(Int(update.position))s / \(Int(update.duration))s"
      )

      PlaybackProgressSyncCoordinator.shared.push(from: model, force: update.forceSync)

    } catch {
      logger.error("Failed to save playback position: \(error.localizedDescription, privacy: .public)")
    }
  }
}
