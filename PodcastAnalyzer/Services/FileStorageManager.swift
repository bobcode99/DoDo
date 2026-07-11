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

  // Captions/SRT files in Documents (user can access via Files app)
  private var captionsDirectory: URL {
    documentsDirectory.appendingPathComponent("Captions", isDirectory: true)
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
      docs.appendingPathComponent("Captions", isDirectory: true),
      docs.appendingPathComponent("Logs", isDirectory: true),
      fm.temporaryDirectory.appendingPathComponent("Downloads", isDirectory: true)
    ]
    for dir in dirs where !fm.fileExists(atPath: dir.path) {
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
  }

  // MARK: - Directory Management

  private func createDirectories() {
    let directories = [audioDirectory, captionsDirectory, logsDirectory, tempDirectory]

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

  // MARK: - Caption Subfolder Helpers

  /// Returns the podcast-specific subfolder inside captionsDirectory.
  /// Path: Captions/{sanitizedPodcastName}/
  private func captionsPodcastDirectory(for podcastTitle: String) -> URL {
    captionsDirectory.appendingPathComponent(sanitizeFileName(podcastTitle), isDirectory: true)
  }

  /// Ensures the podcast subfolder exists, creating it if necessary.
  private func ensureCaptionsPodcastDirectory(for podcastTitle: String) throws {
    let dir = captionsPodcastDirectory(for: podcastTitle)
    guard !fileManager.fileExists(atPath: dir.path) else { return }
    do {
      try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
      logger.info("Created captions subfolder: \(dir.path)")
    } catch {
      logger.error("Failed to create captions subfolder: \(error.localizedDescription, privacy: .public)")
      throw FileStorageError.directoryCreationFailed(error)
    }
  }

  // MARK: - Flat-to-Subfolder Migration

  /// Migrates existing flat caption files from `Captions/{podcast}_{episode}.*` to
  /// `Captions/{podcast}/{episode}.*`.  Safe to call multiple times — already-migrated
  /// files are left untouched.
  func migrateFlatCaptionFilesToSubfolders() {
    guard fileManager.fileExists(atPath: captionsDirectory.path) else { return }

    let contents: [URL]
    do {
      contents = try fileManager.contentsOfDirectory(
        at: captionsDirectory,
        includingPropertiesForKeys: [.isDirectoryKey]
      )
    } catch {
      logger.error("Migration: failed to list Captions directory: \(error.localizedDescription, privacy: .public)")
      return
    }

    var migratedCount = 0

    for fileURL in contents {
      // Skip subdirectories (already migrated files live here)
      if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        continue
      }

      let fileName = fileURL.deletingPathExtension().lastPathComponent
      let ext = fileURL.pathExtension

      // All caption-related files share the flat naming scheme:
      //   {sanitizedPodcast}_{sanitizedEpisode}[_{suffix}].{ext}
      //   where ext is .srt or .json (_wordtimings.json)
      // We need to identify the podcast portion.  Since both parts were sanitized
      // the same way (underscores used as separators), we can't reliably split on
      // the first underscore — instead we enumerate known podcast subfolders that
      // already exist after earlier migrations, plus we attempt a best-effort move
      // using the longest existing-folder prefix match.

      guard ext == "srt" || (ext == "json" && fileName.hasSuffix("_wordtimings")) else {
        continue
      }

      // Try to find a known podcast subfolder whose sanitized name is a prefix of fileName.
      let existingSubfolders: [String]
      do {
        existingSubfolders = try fileManager.contentsOfDirectory(
          at: captionsDirectory,
          includingPropertiesForKeys: [.isDirectoryKey]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .map { $0.lastPathComponent }
      } catch {
        continue
      }

      // Find the matching podcast subfolder (longest prefix match wins).
      let matchingFolder = existingSubfolders
        .filter { fileName.hasPrefix($0 + "_") }
        .max(by: { $0.count < $1.count })

      guard let podcastFolder = matchingFolder else {
        // No subfolder exists yet for this file's podcast.
        // We can't determine the podcast name from the file name alone at this stage,
        // so leave it in place — it will be moved the next time that podcast's
        // caption is saved or accessed via the new path APIs.
        continue
      }

      // Derive the episode portion of the filename.
      let episodePart = String(fileName.dropFirst(podcastFolder.count + 1))  // drop "{podcast}_"
      let newFileName = episodePart + (ext.isEmpty ? "" : ".\(ext)")
      let destinationDir = captionsDirectory.appendingPathComponent(podcastFolder, isDirectory: true)
      let destination = destinationDir.appendingPathComponent(newFileName)

      guard !fileManager.fileExists(atPath: destination.path) else {
        // Already migrated — remove the stale flat file.
        try? fileManager.removeItem(at: fileURL)
        migratedCount += 1
        continue
      }

      do {
        try fileManager.moveItem(at: fileURL, to: destination)
        migratedCount += 1
        logger.info("Migrated caption file: \(fileName).\(ext) → \(podcastFolder)/\(newFileName)")
      } catch {
        logger.error(
          "Migration: failed to move \(fileName).\(ext): \(error.localizedDescription)")
      }
    }

    if migratedCount > 0 {
      logger.info("Caption migration complete: \(migratedCount) file(s) moved.")
    }
  }

  // MARK: - Caption File Management

  /// Generates filename for captions (episode portion only — no podcast prefix).
  func captionFileName(for episodeTitle: String, podcastTitle: String) -> String {
    let sanitizedEpisode = sanitizeFileName(episodeTitle)
    return "\(sanitizedEpisode).srt"
  }

  /// Gets the full path for a caption file.
  /// New path: Captions/{sanitizedPodcast}/{sanitizedEpisode}.srt
  func captionFilePath(for episodeTitle: String, podcastTitle: String) -> URL {
    captionsPodcastDirectory(for: podcastTitle)
      .appendingPathComponent(captionFileName(for: episodeTitle, podcastTitle: podcastTitle))
  }

  /// Checks if caption file exists
  func captionFileExists(for episodeTitle: String, podcastTitle: String) -> Bool {
    let path = captionFilePath(for: episodeTitle, podcastTitle: podcastTitle)
    return fileManager.fileExists(atPath: path.path)
  }

  /// Gets the creation/modification date of a caption file
  func getCaptionFileDate(for episodeTitle: String, podcastTitle: String) -> Date? {
    let path = captionFilePath(for: episodeTitle, podcastTitle: podcastTitle)

    guard fileManager.fileExists(atPath: path.path) else {
      return nil
    }

    do {
      let attributes = try fileManager.attributesOfItem(atPath: path.path)
      // Prefer modification date, fall back to creation date
      if let modDate = attributes[.modificationDate] as? Date {
        return modDate
      }
      return attributes[.creationDate] as? Date
    } catch {
      logger.error("Failed to get caption file date: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  /// Saves caption/SRT file
  func saveCaptionFile(content: String, episodeTitle: String, podcastTitle: String) throws -> URL {
    try ensureCaptionsPodcastDirectory(for: podcastTitle)

    let destinationURL = captionFilePath(for: episodeTitle, podcastTitle: podcastTitle)

    do {
      try content.write(to: destinationURL, atomically: true, encoding: .utf8)
      logger.info("Saved caption file: \(destinationURL.lastPathComponent)")
      return destinationURL
    } catch {
      logger.error("Failed to save caption: \(error.localizedDescription, privacy: .public)")
      throw FileStorageError.saveFailed(error)
    }
  }

  /// Loads caption file content
  func loadCaptionFile(for episodeTitle: String, podcastTitle: String) throws -> String {
    let path = captionFilePath(for: episodeTitle, podcastTitle: podcastTitle)

    guard fileManager.fileExists(atPath: path.path) else {
      throw FileStorageError.fileNotFound
    }

    do {
      return try String(contentsOf: path, encoding: .utf8)
    } catch {
      logger.error("Failed to load caption: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }

  /// Deletes caption file
  func deleteCaptionFile(for episodeTitle: String, podcastTitle: String) throws {
    let path = captionFilePath(for: episodeTitle, podcastTitle: podcastTitle)

    guard fileManager.fileExists(atPath: path.path) else {
      throw FileStorageError.fileNotFound
    }

    do {
      try fileManager.removeItem(at: path)
      logger.info("Deleted caption file: \(path.lastPathComponent)")
    } catch {
      logger.error("Failed to delete caption: \(error.localizedDescription, privacy: .public)")
      throw FileStorageError.deleteFailed(error)
    }
  }

  // MARK: - Word Timing File Management

  /// Generates filename for word timing JSON.
  /// New format: {sanitizedEpisode}_wordtimings.json (inside podcast subfolder)
  private func wordTimingFileName(for episodeTitle: String, podcastTitle: String) -> String {
    let sanitizedEpisode = sanitizeFileName(episodeTitle)
    return "\(sanitizedEpisode)_wordtimings.json"
  }

  /// Gets the full path for a word timing JSON file.
  /// New path: Captions/{sanitizedPodcast}/{sanitizedEpisode}_wordtimings.json
  func wordTimingFilePath(for episodeTitle: String, podcastTitle: String) -> URL {
    captionsPodcastDirectory(for: podcastTitle)
      .appendingPathComponent(wordTimingFileName(for: episodeTitle, podcastTitle: podcastTitle))
  }

  /// Saves word timing JSON alongside the SRT file
  func saveWordTimingFile(content: String, episodeTitle: String, podcastTitle: String) throws -> URL {
    try ensureCaptionsPodcastDirectory(for: podcastTitle)

    let destinationURL = wordTimingFilePath(for: episodeTitle, podcastTitle: podcastTitle)

    do {
      try content.write(to: destinationURL, atomically: true, encoding: .utf8)
      logger.info("Saved word timing file: \(destinationURL.lastPathComponent)")
      return destinationURL
    } catch {
      logger.error("Failed to save word timing: \(error.localizedDescription, privacy: .public)")
      throw FileStorageError.saveFailed(error)
    }
  }

  /// Loads word timing JSON file if it exists
  func loadWordTimingFile(for episodeTitle: String, podcastTitle: String) throws -> String? {
    let path = wordTimingFilePath(for: episodeTitle, podcastTitle: podcastTitle)

    guard fileManager.fileExists(atPath: path.path) else {
      return nil  // Return nil instead of throwing - word timings are optional
    }

    return try String(contentsOf: path, encoding: .utf8)
  }

  /// Checks if word timing file exists
  func wordTimingFileExists(for episodeTitle: String, podcastTitle: String) -> Bool {
    let path = wordTimingFilePath(for: episodeTitle, podcastTitle: podcastTitle)
    return fileManager.fileExists(atPath: path.path)
  }

  /// Deletes word timing file
  func deleteWordTimingFile(for episodeTitle: String, podcastTitle: String) throws {
    let path = wordTimingFilePath(for: episodeTitle, podcastTitle: podcastTitle)

    if fileManager.fileExists(atPath: path.path) {
      try fileManager.removeItem(at: path)
      logger.info("Deleted word timing file: \(path.lastPathComponent)")
    }
  }

  // MARK: - Translated Caption File Management

  /// Generates filename for translated captions.
  /// New format: {sanitizedEpisode}_{langCode}.srt (inside podcast subfolder)
  func translatedCaptionFileName(
    for episodeTitle: String,
    podcastTitle: String,
    targetLanguage: String
  ) -> String {
    let sanitizedEpisode = sanitizeFileName(episodeTitle)
    let langCode = targetLanguage.replacing("-", with: "_")
    return "\(sanitizedEpisode)_\(langCode).srt"
  }

  /// Gets the full path for a translated caption file.
  /// New path: Captions/{sanitizedPodcast}/{sanitizedEpisode}_{langCode}.srt
  func translatedCaptionFilePath(
    for episodeTitle: String,
    podcastTitle: String,
    targetLanguage: String
  ) -> URL {
    captionsPodcastDirectory(for: podcastTitle)
      .appendingPathComponent(
        translatedCaptionFileName(
          for: episodeTitle,
          podcastTitle: podcastTitle,
          targetLanguage: targetLanguage
        )
      )
  }

  /// Checks if translated caption file exists
  func translatedCaptionFileExists(
    for episodeTitle: String,
    podcastTitle: String,
    targetLanguage: String
  ) -> Bool {
    let path = translatedCaptionFilePath(
      for: episodeTitle,
      podcastTitle: podcastTitle,
      targetLanguage: targetLanguage
    )
    return fileManager.fileExists(atPath: path.path)
  }

  /// Saves translated caption/SRT file (bilingual format)
  func saveTranslatedCaptionFile(
    content: String,
    episodeTitle: String,
    podcastTitle: String,
    targetLanguage: String
  ) throws -> URL {
    try ensureCaptionsPodcastDirectory(for: podcastTitle)

    let destinationURL = translatedCaptionFilePath(
      for: episodeTitle,
      podcastTitle: podcastTitle,
      targetLanguage: targetLanguage
    )

    do {
      try content.write(to: destinationURL, atomically: true, encoding: .utf8)
      logger.info("Saved translated caption file: \(destinationURL.lastPathComponent)")
      return destinationURL
    } catch {
      logger.error("Failed to save translated caption: \(error.localizedDescription, privacy: .public)")
      throw FileStorageError.saveFailed(error)
    }
  }

  /// Loads translated caption file content
  func loadTranslatedCaptionFile(
    for episodeTitle: String,
    podcastTitle: String,
    targetLanguage: String
  ) throws -> String {
    let path = translatedCaptionFilePath(
      for: episodeTitle,
      podcastTitle: podcastTitle,
      targetLanguage: targetLanguage
    )

    guard fileManager.fileExists(atPath: path.path) else {
      throw FileStorageError.fileNotFound
    }

    do {
      return try String(contentsOf: path, encoding: .utf8)
    } catch {
      logger.error("Failed to load translated caption: \(error.localizedDescription, privacy: .public)")
      throw error
    }
  }

  /// Deletes translated caption file
  func deleteTranslatedCaptionFile(
    for episodeTitle: String,
    podcastTitle: String,
    targetLanguage: String
  ) throws {
    let path = translatedCaptionFilePath(
      for: episodeTitle,
      podcastTitle: podcastTitle,
      targetLanguage: targetLanguage
    )

    guard fileManager.fileExists(atPath: path.path) else {
      throw FileStorageError.fileNotFound
    }

    do {
      try fileManager.removeItem(at: path)
      logger.info("Deleted translated caption file: \(path.lastPathComponent)")
    } catch {
      logger.error("Failed to delete translated caption: \(error.localizedDescription, privacy: .public)")
      throw FileStorageError.deleteFailed(error)
    }
  }

  /// Gets the creation/modification date of a translated caption file
  func getTranslatedCaptionFileDate(
    for episodeTitle: String,
    podcastTitle: String,
    targetLanguage: String
  ) -> Date? {
    let path = translatedCaptionFilePath(
      for: episodeTitle,
      podcastTitle: podcastTitle,
      targetLanguage: targetLanguage
    )

    guard fileManager.fileExists(atPath: path.path) else {
      return nil
    }

    do {
      let attributes = try fileManager.attributesOfItem(atPath: path.path)
      if let modDate = attributes[.modificationDate] as? Date {
        return modDate
      }
      return attributes[.creationDate] as? Date
    } catch {
      logger.error("Failed to get translated caption file date: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }

  /// Lists all available translation language codes for an episode.
  /// Searches inside the podcast subfolder: Captions/{sanitizedPodcast}/
  func listAvailableTranslations(
    for episodeTitle: String,
    podcastTitle: String
  ) -> Set<String> {
    let podcastDir = captionsPodcastDirectory(for: podcastTitle)
    guard fileManager.fileExists(atPath: podcastDir.path) else { return [] }

    let sanitizedEpisode = sanitizeFileName(episodeTitle)

    do {
      let contents = try fileManager.contentsOfDirectory(
        at: podcastDir,
        includingPropertiesForKeys: nil
      )

      var languageCodes: Set<String> = []

      // Pattern inside the subfolder: {sanitizedEpisode}_{langCode}.srt
      let prefix = sanitizedEpisode + "_"
      let suffix = ".srt"

      for fileURL in contents {
        let fileName = fileURL.lastPathComponent

        // Skip the original caption file (no language suffix)
        if fileName == sanitizedEpisode + ".srt" {
          continue
        }

        if fileName.hasPrefix(prefix) && fileName.hasSuffix(suffix) {
          var langPart = fileName
          langPart.removeFirst(prefix.count)
          langPart.removeLast(suffix.count)

          // Skip word timings file pattern
          if langPart == "wordtimings" {
            continue
          }

          // Convert underscore back to hyphen for standard language codes
          let langCode = langPart.replacing("_", with: "-")
          languageCodes.insert(langCode)
        }
      }

      return languageCodes
    } catch {
      logger.error("Failed to list available translations: \(error.localizedDescription, privacy: .public)")
      return []
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

  /// Clears all caption files from storage (including all podcast subfolders)
  func clearAllCaptionFiles() {
    do {
      let contents = try fileManager.contentsOfDirectory(
        at: captionsDirectory, includingPropertiesForKeys: nil)
      for fileURL in contents {
        try fileManager.removeItem(at: fileURL)
      }
      logger.info("Cleared all caption files/folders (\(contents.count) items)")
    } catch {
      logger.error("Failed to clear caption files: \(error.localizedDescription, privacy: .public)")
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
