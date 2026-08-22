//
//  WatchDownloadModel.swift
//  DoDoWatch
//
//  Watch-local only, never synced. A file path is meaningless on another
//  device, which is the same reason the phone keeps `localAudioPath` out of
//  its CloudKit store (see EpisodeDownloadModel).
//

import Foundation
import SwiftData

@Model
final class WatchDownloadModel {
  #Index<WatchDownloadModel>([\.id])

  /// The project-wide composite key, `"podcastTitle\u{1F}episodeTitle"`.
  var id: String = ""

  var episodeTitle: String = ""
  var podcastTitle: String = ""
  var audioURL: String = ""

  /// Filename inside the audio directory — not an absolute path. The
  /// container's UUID changes between installs, so a stored absolute path goes
  /// stale; the directory is recomputed at read time instead.
  var fileName: String = ""

  var downloadedDate: Date = Date()
  var fileSize: Int64 = 0

  init(
    id: String,
    episodeTitle: String,
    podcastTitle: String,
    audioURL: String,
    fileName: String,
    downloadedDate: Date = Date(),
    fileSize: Int64 = 0
  ) {
    self.id = id
    self.episodeTitle = episodeTitle
    self.podcastTitle = podcastTitle
    self.audioURL = audioURL
    self.fileName = fileName
    self.downloadedDate = downloadedDate
    self.fileSize = fileSize
  }

  var localPath: String {
    WatchAudioStorage.directory.appending(path: fileName).path(percentEncoded: false)
  }
}

/// Where downloaded audio lives on the watch.
///
/// `nonisolated` because the URLSession delegate has to resolve the destination
/// on its own queue — the temp file it is handed is deleted the moment that
/// callback returns, so there is no room for an actor hop first.
nonisolated enum WatchAudioStorage {
  static var directory: URL {
    let base = URL.documentsDirectory.appending(path: "Audio")
    if !FileManager.default.fileExists(atPath: base.path(percentEncoded: false)) {
      try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    return base
  }

  /// Sanitised so the composite key's separator and any path characters in a
  /// title cannot escape the directory.
  static func fileName(for id: String, extension ext: String) -> String {
    let safe = id.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
    return "\(safe.prefix(120)).\(ext)"
  }
}
