//
//  PersistentLogService.swift
//  PodcastAnalyzer
//
//  Exports os.log entries to persistent .log files in Documents/Logs
//  so they can be accessed via the iOS Files app for debugging.
//

import Foundation
import OSLog

@MainActor
final class PersistentLogService {
  static let shared = PersistentLogService()

  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PersistentLog")

  /// The single subsystem all app loggers use.
  private let appSubsystems = ["com.podcast.analyzer"]

  private var logsDirectory: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Logs", isDirectory: true)
  }

  @ObservationIgnored private var exportTask: Task<Void, Never>?

  private init() {}

  // MARK: - Public API

  /// Exports the current session's logs in a background task. Call this when the
  /// session is ending (e.g. scenePhase → .background): OSLogStore with
  /// `.currentProcessIdentifier` scope can only see the running process, so
  /// calling it at launch would capture nothing.
  func exportLogsInBackground() {
    let subsystems = appSubsystems
    let logsDir = logsDirectory
    let log = logger

    exportTask?.cancel()
    exportTask = Task.detached(priority: .utility) {
      do {
        try PersistentLogService.exportLogs(subsystems: subsystems, logsDirectory: logsDir, logger: log)
        PersistentLogService.cleanupOldLogs(logsDirectory: logsDir, keeping: 7, logger: log)
      } catch {
        log.error("Failed to export logs: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  // MARK: - Export

  /// Reads OSLogStore entries from the last 24 hours and writes them to a date-stamped .log file.
  private nonisolated static func exportLogs(
    subsystems: [String],
    logsDirectory: URL,
    logger: Logger
  ) throws {
    let store = try OSLogStore(scope: .currentProcessIdentifier)

    let oneDayAgo = Date().addingTimeInterval(-24 * 60 * 60)
    let position = store.position(date: oneDayAgo)

    let entries = try store.getEntries(at: position)

    // Filter to our app's subsystems
    let appEntries = entries.compactMap { $0 as? OSLogEntryLog }.filter { entry in
      subsystems.contains(entry.subsystem)
    }

    guard !appEntries.isEmpty else {
      logger.info("No app log entries found in the last 24 hours — skipping export")
      return
    }

    // Format entries
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS Z"
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")

    var lines: [String] = []
    lines.reserveCapacity(appEntries.count)

    for entry in appEntries {
      let timestamp = dateFormatter.string(from: entry.date)
      let level = levelString(for: entry.level)
      let category = entry.category
      let message = entry.composedMessage
      lines.append("[\(timestamp)] [\(level)] [\(entry.subsystem)/\(category)] \(message)")
    }

    let content = lines.joined(separator: "\n")

    // Ensure directory exists
    if !FileManager.default.fileExists(atPath: logsDirectory.path) {
      try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    // Write to file
    let fileFormatter = DateFormatter()
    fileFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
    fileFormatter.locale = Locale(identifier: "en_US_POSIX")
    let fileName = "PodcastAnalyzer_\(fileFormatter.string(from: Date())).log"
    let fileURL = logsDirectory.appendingPathComponent(fileName)

    try content.write(to: fileURL, atomically: true, encoding: .utf8)
    logger.info("Exported \(appEntries.count) log entries to \(fileName)")
  }

  // MARK: - Cleanup

  /// Removes log files older than the most recent `keeping` files.
  private nonisolated static func cleanupOldLogs(
    logsDirectory: URL,
    keeping: Int,
    logger: Logger
  ) {
    guard FileManager.default.fileExists(atPath: logsDirectory.path) else { return }

    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: logsDirectory,
        includingPropertiesForKeys: [.creationDateKey],
        options: .skipsHiddenFiles
      )

      let logFiles = contents
        .filter { $0.pathExtension == "log" }
        .sorted { a, b in
          let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
          let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
          return dateA > dateB  // newest first
        }

      guard logFiles.count > keeping else { return }

      let filesToRemove = logFiles.dropFirst(keeping)
      for file in filesToRemove {
        try FileManager.default.removeItem(at: file)
        logger.info("Removed old log file: \(file.lastPathComponent)")
      }
    } catch {
      logger.error("Failed to cleanup old logs: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Helpers

  private nonisolated static func levelString(for level: OSLogEntryLog.Level) -> String {
    switch level {
    case .undefined: return "UNDEFINED"
    case .debug:     return "DEBUG"
    case .info:      return "INFO"
    case .notice:    return "NOTICE"
    case .error:     return "ERROR"
    case .fault:     return "FAULT"
    @unknown default: return "UNKNOWN"
    }
  }
}
