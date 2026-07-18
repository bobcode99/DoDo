//
//  FileStorageError.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/17.
//

//
//  FileStorageManager.swift
//  PodcastAnalyzer
//
//  Manages file storage for podcast audio, images, and captions
//

import Foundation
import OSLog

enum FileStorageError: LocalizedError {
  case invalidURL
  case fileNotFound
  case saveFailed(Error)
  case deleteFailed(Error)
  case directoryCreationFailed(Error)

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid file URL"
    case .fileNotFound:
      return "File not found"
    case .saveFailed(let error):
      return "Failed to save file: \(error.localizedDescription)"
    case .deleteFailed(let error):
      return "Failed to delete file: \(error.localizedDescription)"
    case .directoryCreationFailed(let error):
      return "Failed to create directory: \(error.localizedDescription)"
    }
  }
}

actor FileStorageManager {
  static let shared = FileStorageManager()

  private let fileManager = FileManager.default
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "FileStorage")

  // MARK: - Directory Structure

  private var documentsDirectory: URL {
    fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  private var libraryDirectory: URL {
    fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
  }

  // Audio files in Application Support (proper location for macOS app-managed files)
  private var audioDirectory: URL {
    Self.platformAudioDirectory(fileManager: fileManager)
  }

  /// Audio storage directory: Application Support on macOS (better permissions for app-managed
  /// files), Library on iOS. `nonisolated` so callers off the actor (background scans, other
  /// services) don't need to hop through `FileStorageManager.shared`.
  nonisolated static func platformAudioDirectory(fileManager: FileManager = .default) -> URL {
    #if os(macOS)
    let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return appSupport.appendingPathComponent("PodcastAnalyzer/Audio", isDirectory: true)
    #else
    let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    return library.appendingPathComponent("Audio", isDirectory: true)
    #endif
  }

  // Log files in Documents (user can access via Files app)
  var logsDirectory: URL {
    documentsDirectory.appendingPathComponent("Logs", isDirectory: true)
  }

  // Temporary downloads
  private var tempDirectory: URL {
    fileManager.temporaryDirectory.appendingPathComponent("Downloads", isDirectory: true)
  }

  private init() {
    // Compute directory URLs inline (actor computed properties aren't accessible from nonisolated init)
    let fm = FileManager.default
    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let dirs = [
      Self.platformAudioDirectory(fileManager: fm),
      docs.appendingPathComponent("Logs", isDirectory: true),
      fm.temporaryDirectory.appendingPathComponent("Downloads", isDirectory: true)
    ]
    for dir in dirs where !fm.fileExists(atPath: dir.path) {
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
  }

  // MARK: - Directory Management

  private func createDirectories() {
    let directories = [audioDirectory, logsDirectory, tempDirectory]

    for directory in directories {
      // Only create if it doesn't exist
      if !fileManager.fileExists(atPath: directory.path) {
        do {
          try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
          logger.info("Created directory: \(directory.path)")
        } catch {
          logger.error(
            "Failed to create directory \(directory.path): \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: - Audio File Management

  /// Generates a unique filename for an episode's audio file
  /// Note: Extension will be added when saving based on the actual file type
  func audioFileName(for episodeTitle: String, podcastTitle: String, extension: String = "m4a")
    -> String
  {
    let sanitized = sanitizeFileName("\(podcastTitle)_\(episodeTitle)")
    return "\(sanitized).\(`extension`)"
  }

  /// Gets the full path for an audio file (returns actual file if it exists)
  func audioFilePath(for episodeTitle: String, podcastTitle: String) -> URL {
    let baseFileName = sanitizeFileName("\(podcastTitle)_\(episodeTitle)")
    let possibleExtensions = ["mp3", "m4a", "aac", "wav", "flac"]

    // Find the actual file
    for ext in possibleExtensions {
      let path = self.audioDirectory.appendingPathComponent("\(baseFileName).\(ext)")
      if fileManager.fileExists(atPath: path.path) {
        return path
      }
    }

    // Default to m4a if not found
    return audioDirectory.appendingPathComponent(
      audioFileName(for: episodeTitle, podcastTitle: podcastTitle))
  }

  /// Checks if audio file exists (checks multiple extensions)
  func audioFileExists(for episodeTitle: String, podcastTitle: String) -> Bool {
    let baseFileName = sanitizeFileName("\(podcastTitle)_\(episodeTitle)")
    let possibleExtensions = ["mp3", "m4a", "aac", "wav", "flac"]

    for ext in possibleExtensions {
      let path = self.audioDirectory.appendingPathComponent("\(baseFileName).\(ext)")
      if fileManager.fileExists(atPath: path.path) {
        return true
      }
    }
    return false
  }

  /// Saves downloaded audio file
  func saveAudioFile(from sourceURL: URL, episodeTitle: String, podcastTitle: String) throws -> URL
  {
    // Ensure audio directory exists with proper permissions
    let directoryURL = self.audioDirectory
    if !fileManager.fileExists(atPath: directoryURL.path) {
      do {
        // Create with intermediate directories and proper attributes
        try fileManager.createDirectory(
          at: directoryURL,
          withIntermediateDirectories: true,
          attributes: nil
        )
        logger.info("Created audio directory: \(directoryURL.path)")
      } catch {
        logger.error("Failed to create audio directory: \(error.localizedDescription, privacy: .public)")
        throw FileStorageError.directoryCreationFailed(error)
      }
    } else {
      // Verify directory is writable
      guard fileManager.isWritableFile(atPath: directoryURL.path) else {
        logger.error("Audio directory exists but is not writable: \(directoryURL.path)")
        throw FileStorageError.directoryCreationFailed(
          NSError(
            domain: "FileStorageError",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Audio directory is not writable"]
          )
        )
      }
    }

    // Detect file extension from source file, filtering out temp extensions
    var fileExtension = sourceURL.pathExtension.lowercased()
    let validExtensions = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"]
    if fileExtension.isEmpty || !validExtensions.contains(fileExtension) {
      fileExtension = "mp3"  // Default to mp3 if unknown
    }

    let fileName = audioFileName(
      for: episodeTitle, podcastTitle: podcastTitle, extension: fileExtension)
    let destinationURL = self.audioDirectory.appendingPathComponent(fileName)

    // Remove existing files with ALL extensions (including destination)
    let baseFileName = sanitizeFileName("\(podcastTitle)_\(episodeTitle)")
    let possibleExtensions = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "tmp"]
    for ext in possibleExtensions {
      let possiblePath = self.audioDirectory.appendingPathComponent("\(baseFileName).\(ext)")
      if fileManager.fileExists(atPath: possiblePath.path) {
        try? fileManager.removeItem(at: possiblePath)
        logger.info("Removed existing file: \(possiblePath.lastPathComponent)")
      }
    }

    // Also remove destination if it still exists
    if fileManager.fileExists(atPath: destinationURL.path) {
      try? fileManager.removeItem(at: destinationURL)
    }

    do {
      // Try move first (faster), fall back to copy+delete if move fails
      do {
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        logger.info(
          "Saved audio file: \(destinationURL.lastPathComponent) with extension: \(fileExtension)")
        return destinationURL
      } catch {
        // If move fails (e.g., cross-volume), try copy + delete
        logger.warning("Move failed, trying copy: \(error.localizedDescription, privacy: .public)")
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        // Try to remove source, but don't fail if it doesn't exist
        try? fileManager.removeItem(at: sourceURL)
        logger.info(
          "Saved audio file (via copy): \(destinationURL.lastPathComponent) with extension: \(fileExtension)")
        return destinationURL
      }
    } catch {
      logger.error("Failed to save audio: \(error.localizedDescription, privacy: .public)")
      throw FileStorageError.saveFailed(error)
    }
  }

  /// Deletes audio file (checks all possible extensions)
  func deleteAudioFile(for episodeTitle: String, podcastTitle: String) throws {
    let baseFileName = sanitizeFileName("\(podcastTitle)_\(episodeTitle)")
    let possibleExtensions = ["mp3", "m4a", "aac", "wav", "flac"]
    var deleted = false

    for ext in possibleExtensions {
      let path = self.audioDirectory.appendingPathComponent("\(baseFileName).\(ext)")
      if fileManager.fileExists(atPath: path.path) {
        do {
          try fileManager.removeItem(at: path)
          logger.info("Deleted audio file: \(path.lastPathComponent)")
          deleted = true
        } catch {
          logger.error("Failed to delete audio: \(error.localizedDescription, privacy: .public)")
          throw FileStorageError.deleteFailed(error)
        }
      }
    }

    if !deleted {
      throw FileStorageError.fileNotFound
    }
  }

  // MARK: - Storage Info

  /// Gets total size of stored audio files
  func getTotalAudioSize() -> Int64 {
    guard
      let enumerator = fileManager.enumerator(
        at: audioDirectory, includingPropertiesForKeys: [.fileSizeKey])
    else {
      return 0
    }

    var totalSize: Int64 = 0
    for case let fileURL as URL in enumerator {
      guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
        let fileSize = resourceValues.fileSize
      else {
        continue
      }
      totalSize += Int64(fileSize)
    }

    return totalSize
  }

  /// Formats bytes to human-readable string
  func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB, .useKB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }

  /// Calculates total audio size (async wrapper)
  func calculateTotalAudioSize() -> Int64 {
    getTotalAudioSize()
  }

  // MARK: - Bulk Delete Operations

  /// Clears all audio files from storage
  func clearAllAudioFiles() {
    do {
      let contents = try fileManager.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: nil)
      for fileURL in contents {
        try fileManager.removeItem(at: fileURL)
      }
      logger.info("Cleared all audio files (\(contents.count) files)")
    } catch {
      logger.error("Failed to clear audio files: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// Clears all log files from storage
  func clearAllLogFiles() {
    do {
      let contents = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
      for fileURL in contents {
        try fileManager.removeItem(at: fileURL)
      }
      logger.info("Cleared all log files (\(contents.count) files)")
    } catch {
      logger.error("Failed to clear log files: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Helpers

  private func sanitizeFileName(_ fileName: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
    return
      fileName
      .components(separatedBy: invalidCharacters)
      .joined(separator: "_")
      .trimmingCharacters(in: .whitespaces)
  }
}
