//
//  WatchProgressStore.swift
//  DoDoWatch
//
//  Reads and writes PlaybackProgressModel — the CloudKit-mirrored row the
//  phone and Mac also write. This is the whole of watch↔phone progress sync:
//  no comparator, no message passing. Pocket Casts needs both because their
//  truth lives on their own server; ours lives in the user's private database,
//  which Apple already replicates to the watch.
//

import Foundation
import SwiftData

@MainActor
final class WatchProgressStore {
  static let shared = WatchProgressStore()

  private var context: ModelContext?

  private init() {}

  func setModelContainer(_ container: ModelContainer) {
    context = container.mainContext
  }

  /// Saved position for an episode, or 0 if this Apple ID has never played it.
  func position(for id: String) -> TimeInterval {
    guard let context else { return 0 }
    let descriptor = FetchDescriptor<PlaybackProgressModel>(
      predicate: #Predicate { $0.id == id }
    )
    guard let row = try? context.fetch(descriptor).first else { return 0 }
    // A finished episode restarts rather than resuming one second from the end.
    return row.isCompleted ? 0 : row.lastPlaybackPosition
  }

  func record(id: String, position: TimeInterval, duration: TimeInterval) {
    guard let context else { return }

    let descriptor = FetchDescriptor<PlaybackProgressModel>(
      predicate: #Predicate { $0.id == id }
    )
    let row = try? context.fetch(descriptor).first

    // Treat the last 30s as finished, matching how the phone marks completion
    // rather than requiring the user to sit through trailing credits.
    let isCompleted = duration > 0 && position >= duration - 30

    if let row {
      row.lastPlaybackPosition = position
      if duration > 0 { row.duration = duration }
      row.isCompleted = isCompleted
      if isCompleted { row.lastPlayedDate = Date() }
      row.updatedAt = Date()
      row.deviceName = Self.deviceName
    } else {
      context.insert(
        PlaybackProgressModel(
          id: id,
          lastPlaybackPosition: position,
          duration: duration,
          isCompleted: isCompleted,
          lastPlayedDate: isCompleted ? Date() : nil,
          updatedAt: Date(),
          deviceName: Self.deviceName
        )
      )
    }
    try? context.save()
  }

  /// Diagnostic only — the phone never merges on this, only on `updatedAt`.
  private static let deviceName = "Apple Watch"
}
