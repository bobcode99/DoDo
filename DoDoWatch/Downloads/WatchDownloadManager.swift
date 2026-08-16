//
//  WatchDownloadManager.swift
//  DoDoWatch
//
//  Pulls episode audio straight off the internet over Wi-Fi/LTE.
//
//  Not WCSession.transferFile: relaying through the phone would make it a
//  required participant in a feature whose whole point is that the watch works
//  alone, and it needs its own transfer queue on top. Pocket Casts reaches the
//  same conclusion — their watch downloads run through the ordinary
//  DownloadManager against a cellular background session.
//

import Foundation
import Observation
import OSLog
import SwiftData
import WatchKit

private nonisolated let logger = Logger(
  subsystem: "com.jn.PodcastAnalyzer.watch", category: "Downloads")

@MainActor
@Observable
final class WatchDownloadManager {
  static let shared = WatchDownloadManager()

  /// Composite keys currently downloading, with 0…1 progress.
  private(set) var inFlight: [String: Double] = [:]

  @ObservationIgnored private var context: ModelContext?
  @ObservationIgnored private let delegate = DownloadDelegate()

  /// Survives the app being suspended, which on a watch is most of the time —
  /// but watchOS defers these at its own discretion, so a download started
  /// while the user is looking at the screen may simply not move.
  @ObservationIgnored private lazy var backgroundSession: URLSession = {
    let config = URLSessionConfiguration.background(
      withIdentifier: "com.jn.PodcastAnalyzer.watchkitapp.downloads")
    config.sessionSendsLaunchEvents = true
    config.allowsCellularAccess = true
    return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
  }()

  /// Runs immediately, so tapping Download does something visible.
  @ObservationIgnored private lazy var foregroundSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.allowsCellularAccess = true
    return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
  }()

  /// Which session a new task goes on. Same rule as Pocket Casts
  /// (DownloadManager.swift:562-566): foreground while the user is watching,
  /// background otherwise.
  ///
  /// Known gap: a foreground download is not migrated to the background
  /// session when the app resigns active, so backgrounding mid-download loses
  /// it. Pocket Casts does migrate (transferForegroundDownloadsToBackground).
  private var sessionForNewTask: URLSession {
    WKApplication.shared().applicationState == .active ? foregroundSession : backgroundSession
  }

  private init() {}

  func setModelContainer(_ container: ModelContainer) {
    context = container.mainContext
    delegate.owner = self
    // Touch the background session so it reconnects to any downloads that
    // finished while the app was not running.
    _ = backgroundSession
  }

  // MARK: - Queries

  func downloadedModel(for id: String) -> WatchDownloadModel? {
    guard let context else { return nil }
    let descriptor = FetchDescriptor<WatchDownloadModel>(predicate: #Predicate { $0.id == id })
    guard let row = try? context.fetch(descriptor).first else { return nil }
    // A row whose file vanished (offloaded, reinstalled) is worse than no row.
    guard FileManager.default.fileExists(atPath: row.localPath) else {
      context.delete(row)
      try? context.save()
      return nil
    }
    return row
  }

  func isDownloaded(_ id: String) -> Bool { downloadedModel(for: id) != nil }

  // MARK: - Actions

  func download(_ episode: WatchPlayableEpisode) {
    guard !isDownloaded(episode.progressKey), inFlight[episode.progressKey] == nil,
      let url = URL(string: episode.audioURL)
    else { return }

    let task = sessionForNewTask.downloadTask(with: url)
    // The key rides on the task rather than in a dictionary the delegate would
    // have to share across isolation domains — background tasks also outlive
    // any in-memory map when the app is relaunched.
    //
    // Record separator, not unit separator: progressKey already contains a
    // U+001F of its own, so splitting on that yielded five fields and the
    // delegate silently dropped every finished download.
    task.taskDescription = [
      episode.progressKey, episode.podcastTitle, episode.title, episode.audioURL,
    ].joined(separator: TaskFields.separator)

    // Watch schedulers want a size hint; podcast servers often omit
    // Content-Length. 20 MB is roughly a 40-minute show and is the same
    // stand-in Pocket Casts uses (DownloadManager.swift:765).
    task.countOfBytesClientExpectsToReceive = 20 * 1024 * 1024

    inFlight[episode.progressKey] = 0
    task.resume()
  }

  func delete(id: String) {
    guard let context, let row = downloadedModel(for: id) else { return }
    try? FileManager.default.removeItem(atPath: row.localPath)
    context.delete(row)
    try? context.save()
  }

  // MARK: - Delegate callbacks

  fileprivate func updateProgress(key: String, fraction: Double) {
    inFlight[key] = fraction
  }

  fileprivate func finish(_ result: CompletedDownload) {
    guard let context else { return }
    inFlight[result.key] = nil

    let key = result.key
    let existing = try? context.fetch(
      FetchDescriptor<WatchDownloadModel>(predicate: #Predicate { $0.id == key })
    ).first
    if let existing { context.delete(existing) }

    context.insert(
      WatchDownloadModel(
        id: result.key,
        episodeTitle: result.episodeTitle,
        podcastTitle: result.podcastTitle,
        audioURL: result.audioURL,
        fileName: result.fileName,
        fileSize: result.fileSize
      )
    )
    try? context.save()
  }

  fileprivate func fail(key: String) {
    inFlight[key] = nil
  }

  // MARK: - Background relaunch

  /// watchOS relaunches the app to hand back a finished background session;
  /// the task must be held open until URLSession says it is done flushing.
  func handle(_ task: WKURLSessionRefreshBackgroundTask) {
    _ = backgroundSession
    delegate.pendingBackgroundTasks.append(task)
  }
}

/// How the episode's identity is packed onto `URLSessionTask.taskDescription`.
private nonisolated enum TaskFields {
  /// U+001E. Must not be U+001F — the composite episode key already uses that
  /// between podcast and episode title.
  static let separator = "\u{1E}"
}

/// What survives the hop from the session's background queue to the main actor.
private struct CompletedDownload: Sendable {
  let key: String
  let podcastTitle: String
  let episodeTitle: String
  let audioURL: String
  let fileName: String
  let fileSize: Int64
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
  /// Set once at startup, read on the main actor only.
  @MainActor weak var owner: WatchDownloadManager?
  @MainActor var pendingBackgroundTasks: [WKURLSessionRefreshBackgroundTask] = []

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    // URLSession deletes `location` the moment this returns, so the move must
    // happen here rather than after any await.
    guard let fields = downloadTask.taskDescription?.components(
      separatedBy: TaskFields.separator), fields.count == 4
    else {
      logger.error("Unparseable taskDescription; download discarded")
      return
    }

    let key = fields[0]
    let ext = downloadTask.originalRequest?.url?.pathExtension
    let fileName = WatchAudioStorage.fileName(
      for: key, extension: (ext?.isEmpty == false ? ext! : "mp3"))
    let destination = WatchAudioStorage.directory.appending(path: fileName)

    do {
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.moveItem(at: location, to: destination)
    } catch {
      logger.error("Move failed: \(error.localizedDescription, privacy: .public)")
      Task { @MainActor in self.owner?.fail(key: key) }
      return
    }

    let attributes = try? FileManager.default.attributesOfItem(
      atPath: destination.path(percentEncoded: false))
    let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

    let result = CompletedDownload(
      key: key,
      podcastTitle: fields[1],
      episodeTitle: fields[2],
      audioURL: fields[3],
      fileName: fileName,
      fileSize: size
    )
    Task { @MainActor in self.owner?.finish(result) }
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0,
      let key = downloadTask.taskDescription?.components(
        separatedBy: TaskFields.separator).first
    else { return }
    let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    Task { @MainActor in self.owner?.updateProgress(key: key, fraction: fraction) }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    guard let error,
      let key = task.taskDescription?.components(
        separatedBy: TaskFields.separator).first
    else { return }
    logger.error("Download failed: \(error.localizedDescription, privacy: .public)")
    Task { @MainActor in self.owner?.fail(key: key) }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    Task { @MainActor in
      self.pendingBackgroundTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
      self.pendingBackgroundTasks.removeAll()
    }
  }
}
