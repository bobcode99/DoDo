//
//  ModelContext+Save.swift
//  PodcastAnalyzer
//
//  `try? context.save()` is the wrong default: a SwiftData save can fail for
//  reasons the user then experiences as data loss (a star that doesn't stick, a
//  position that resets), and swallowing the error leaves nothing behind to
//  diagnose it with. This logs instead, capturing the call site automatically
//  so the log line says which write failed.
//

import Foundation
import OSLog
import SwiftData

extension ModelContext {
  private static let logger = Logger(subsystem: "com.podcast.analyzer", category: "SwiftData")

  /// Save, logging any failure with the calling function's name.
  /// Returns whether the save succeeded, for the rare caller that must branch.
  @discardableResult
  func saveOrLog(_ context: String = #function) -> Bool {
    do {
      try save()
      return true
    } catch {
      Self.logger.error(
        "Save failed in \(context, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return false
    }
  }
}
