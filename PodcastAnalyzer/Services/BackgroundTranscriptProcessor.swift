import Foundation
import Observation
import OSLog

#if os(iOS)
import UIKit
#endif

@MainActor
@Observable
final class BackgroundTranscriptProcessor {
  static let shared = BackgroundTranscriptProcessor()

  var isEnabled: Bool = false {
    didSet { UserDefaults.standard.set(isEnabled, forKey: Keys.enabled) }
  }

  var isProcessing = false
  var pendingCount = 0
  var processedCount = 0

  @ObservationIgnored
  private var monitorTask: Task<Void, Never>?
  @ObservationIgnored
  private var processingTask: Task<Void, Never>?
  @ObservationIgnored
  private let logger = Logger(subsystem: "com.podcast.analyzer", category: "BackgroundTranscriptProcessor")

  private enum Keys {
    static let enabled = "autoTranscribeWhileCharging"
  }

  private init() {
    isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled)
  }

  // MARK: - Charging Monitor

  func startMonitoring() {
    #if os(iOS)
    UIDevice.current.isBatteryMonitoringEnabled = true
    monitorTask?.cancel()
    monitorTask = Task { [weak self] in
      for await _ in NotificationCenter.default.notifications(
        named: UIDevice.batteryStateDidChangeNotification
      ) {
        guard let self, !Task.isCancelled else { return }
        let state = UIDevice.current.batteryState
        if self.isEnabled && (state == .charging || state == .full) {
          self.logger.info("Device charging — starting auto-transcription")
          // processAll needs podcasts from the caller; we post a notification
          // so the app layer with ModelContext access can provide them
          NotificationCenter.default.post(name: .autoTranscribeTriggered, object: nil)
        }
      }
    }
    #endif
  }

  func stopMonitoring() {
    monitorTask?.cancel()
    monitorTask = nil
  }

  var isCharging: Bool {
    #if os(iOS)
    let state = UIDevice.current.batteryState
    return state == .charging || state == .full
    #else
    return false
    #endif
  }

  // MARK: - Processing

  func processAll(podcasts: [PodcastInfoModel]) {
    guard !isProcessing else { return }

    processingTask?.cancel()
    processingTask = Task { [weak self] in
      guard let self else { return }
      self.isProcessing = true
      self.processedCount = 0

      let storage = FileStorageManager.shared
      var episodesToProcess: [(episodeTitle: String, podcastTitle: String, audioPath: String, language: String)] = []

      for podcast in podcasts {
        if Task.isCancelled { break }
        let info = podcast.podcastInfo
        for episode in info.episodes {
          if Task.isCancelled { break }
          let hasTranscript = await storage.captionFileExists(
            for: episode.title, podcastTitle: info.title
          )
          guard !hasTranscript else { continue }

          if let audioURL = episode.audioURL {
            let downloadState = DownloadManager.shared.getDownloadState(episodeTitle: episode.title, podcastTitle: info.title)
            if case .downloaded(let path) = downloadState {
              episodesToProcess.append((
                episodeTitle: episode.title,
                podcastTitle: info.title,
                audioPath: path,
                language: info.language
              ))
            }
          }
        }
      }

      self.pendingCount = episodesToProcess.count
      self.logger.info("Found \(episodesToProcess.count) episodes to transcribe")

      for item in episodesToProcess {
        if Task.isCancelled { break }

        #if os(iOS)
        let state = UIDevice.current.batteryState
        if state != .charging && state != .full {
          self.logger.info("Device unplugged — pausing auto-transcription")
          break
        }
        #endif

        TranscriptManager.shared.queueTranscript(
          episodeTitle: item.episodeTitle,
          podcastTitle: item.podcastTitle,
          audioPath: item.audioPath,
          language: item.language
        )
        self.processedCount += 1
      }

      self.isProcessing = false
      self.logger.info("Auto-transcription finished: \(self.processedCount) queued")
    }
  }

  func cancelProcessing() {
    processingTask?.cancel()
    processingTask = nil
    isProcessing = false
  }
}

extension Notification.Name {
  static let autoTranscribeTriggered = Notification.Name("autoTranscribeTriggered")
}
