//
//  PlaybackProgressSyncCoordinator.swift
//  PodcastAnalyzer
//
//  Bridges local playback-position saves (EpisodeDownloadModel, every 5s
//  during playback) to the CloudKit-synced PlaybackProgressModel, and applies
//  incoming iCloud changes back onto local state so "pause on iPhone, resume
//  on Mac" works across devices signed into the same Apple ID.
//

import Foundation
import CoreData
import SwiftData
import OSLog
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Pure merge/throttle logic (no SwiftData — unit-testable in isolation)

nonisolated enum PlaybackProgressMerge {
  /// A full CloudKit round trip on every 5s local save would burn quota and
  /// battery for zero benefit (scrubbing/resume only need the *local*
  /// EpisodeDownloadModel). Push the synced record at most every
  /// `minInterval` seconds unless the caller forces it (pause, episode
  /// switch, completion, app backgrounding).
  static func shouldPush(now: Date, lastPushedAt: Date?, minInterval: TimeInterval, force: Bool) -> Bool {
    if force { return true }
    guard let lastPushedAt else { return true }
    return now.timeIntervalSince(lastPushedAt) >= minInterval
  }

  /// Last-writer-wins by timestamp. A remote row only overwrites local state
  /// when it is strictly newer than the last known local write — otherwise a
  /// stale/duplicate remote-change notification (or this device's own echoed
  /// write) would clobber more recent local progress.
  static func isRemoteNewer(remoteUpdatedAt: Date, localUpdatedAt: Date?) -> Bool {
    remoteUpdatedAt > (localUpdatedAt ?? .distantPast)
  }
}

// MARK: - Coordinator

@MainActor
final class PlaybackProgressSyncCoordinator {
  static let shared = PlaybackProgressSyncCoordinator()

  /// Push cadence while actively playing.
  private let minPushInterval: TimeInterval = 30

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PlaybackProgressSync")
  private var context: ModelContext?
  private var remoteChangeObserver: NSObjectProtocol?
  private var lastPushedAt: [String: Date] = [:]

  private static let deviceName: String = {
    #if os(iOS)
    UIDevice.current.name
    #elseif os(macOS)
    Host.current().localizedName ?? "Mac"
    #else
    "Unknown Device"
    #endif
  }()

  // Internal (not private) so tests can create an isolated instance against
  // an in-memory container instead of sharing app-wide singleton state.
  init() {}

  func setModelContainer(_ container: ModelContainer) {
    guard context == nil else { return }
    // Share the main context (same one PlaybackStateCoordinator writes
    // through) rather than a private one: a merged remote row needs to be
    // visible immediately to the UI's @Query-bound views, and a separate
    // context wouldn't see this device's own just-saved local writes without
    // an explicit cross-context merge.
    context = container.mainContext
    observeRemoteChanges()
  }

  // MARK: - Push (local → CloudKit)

  /// Call after every local `EpisodeDownloadModel` playback save. Set
  /// `force` on pause, episode switch, completion, and app backgrounding so
  /// those moments always reach other devices even between throttle windows.
  func push(from model: EpisodeDownloadModel, force: Bool = false) {
    guard let context else { return }
    let now = Date()
    guard PlaybackProgressMerge.shouldPush(
      now: now, lastPushedAt: lastPushedAt[model.id], minInterval: minPushInterval, force: force
    ) else { return }

    let id = model.id
    let descriptor = FetchDescriptor<PlaybackProgressModel>(predicate: #Predicate { $0.id == id })
    do {
      let record: PlaybackProgressModel
      if let existing = try context.fetch(descriptor).first {
        record = existing
      } else {
        record = PlaybackProgressModel(id: id)
        context.insert(record)
      }
      record.lastPlaybackPosition = model.lastPlaybackPosition
      record.duration = model.duration
      record.isCompleted = model.isCompleted
      record.playCount = model.playCount
      record.lastPlayedDate = model.lastPlayedDate
      record.updatedAt = now
      record.deviceName = Self.deviceName

      try context.save()
      lastPushedAt[id] = now
    } catch {
      logger.error("Failed to push playback progress: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Pull (CloudKit → local)

  private func observeRemoteChanges() {
    remoteChangeObserver = NotificationCenter.default.addObserver(
      forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.mergeIncomingChanges()
      }
    }
  }

  /// Runs on every remote-change notification (cheap local SQLite scan, no
  /// network — CloudKit already delivered the data by the time this fires).
  /// Internal (not private) so tests can drive a merge without a live
  /// CloudKit round trip.
  func mergeIncomingChanges() {
    guard let context else { return }
    do {
      let progressRows = try context.fetch(FetchDescriptor<PlaybackProgressModel>())
      var didChange = false
      for row in progressRows {
        let id = row.id
        let localDescriptor = FetchDescriptor<EpisodeDownloadModel>(predicate: #Predicate { $0.id == id })
        guard let localModel = try context.fetch(localDescriptor).first else { continue }
        guard PlaybackProgressMerge.isRemoteNewer(
          remoteUpdatedAt: row.updatedAt, localUpdatedAt: localModel.progressUpdatedAt
        ) else { continue }
        apply(row, to: localModel)
        didChange = true
      }
      if didChange {
        try context.save()
      }
    } catch {
      logger.error("Failed to merge incoming playback progress: \(error.localizedDescription, privacy: .public)")
    }
  }

  func apply(_ remote: PlaybackProgressModel, to local: EpisodeDownloadModel) {
    let completionChanged = remote.isCompleted != local.isCompleted

    local.lastPlaybackPosition = remote.lastPlaybackPosition
    if remote.duration > 0 { local.duration = remote.duration }
    local.playCount = remote.playCount
    local.isCompleted = remote.isCompleted
    // Reassign after isCompleted: its didSet stamps `lastPlayedDate = Date()`
    // on a false→true transition, which would otherwise clobber this with
    // "now" instead of the actual remote completion time.
    if let remoteLastPlayed = remote.lastPlayedDate {
      local.lastPlayedDate = remoteLastPlayed
    }
    local.progressUpdatedAt = remote.updatedAt

    if completionChanged {
      NotificationCenter.default.post(name: .episodeCompletionChanged, object: nil)
    }
    logger.info(
      "Applied incoming playback progress for \(remote.id, privacy: .public) from \(remote.deviceName, privacy: .public)"
    )
  }
}
