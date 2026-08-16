//
//  CloudSyncStatus.swift
//  PodcastAnalyzer
//
//  Observable view of what CloudKit mirroring is actually doing.
//
//  Worth surfacing because the failure modes are silent: SwiftData falls back
//  to a local-only store when there is no iCloud account, and a rejected
//  record type shows up as "my other device never got this" with nothing in
//  the UI to explain it. The watch app made that acutely obvious — it has no
//  other source of data at all.
//

import CloudKit
import CoreData
import Foundation
import Observation
import OSLog

private nonisolated let logger = Logger(subsystem: "com.podcast.analyzer", category: "CloudSync")

@MainActor
@Observable
final class CloudSyncStatus {
  static let shared = CloudSyncStatus()

  enum AccountState: Equatable {
    case unknown
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine(String)

    var isUsable: Bool { self == .available }
  }

  /// One CloudKit mirroring event — a setup, an import, or an export.
  struct Activity: Identifiable, Equatable {
    let id = UUID()
    let kind: String
    let started: Date
    let ended: Date?
    let succeeded: Bool
    let errorDescription: String?

    var isRunning: Bool { ended == nil }
  }

  /// Same container as `PodcastAnalyzerApp.cloudKitContainerIdentifier`;
  /// duplicated rather than referenced so this stays usable from previews and
  /// tests that never build the app's scene.
  static let containerIdentifier = "iCloud.com.jn.PodcastAnalyzer"

  private(set) var account: AccountState = .unknown
  private(set) var lastImport: Activity?
  private(set) var lastExport: Activity?
  private(set) var lastSetup: Activity?

  @ObservationIgnored private var observer: NSObjectProtocol?

  private init() {
    observeEvents()
  }

  // MARK: - Account

  func refreshAccountStatus() async {
    let container = CKContainer(identifier: Self.containerIdentifier)
    do {
      let status = try await container.accountStatus()
      account =
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        default: .couldNotDetermine("Status \(status.rawValue)")
        }
    } catch {
      account = .couldNotDetermine(error.localizedDescription)
    }
  }

  // MARK: - Events

  private func observeEvents() {
    observer = NotificationCenter.default.addObserver(
      forName: NSPersistentCloudKitContainer.eventChangedNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      // The notification is delivered on the main queue, so reading it here and
      // hopping with the extracted values keeps `Event` (non-Sendable) put.
      guard
        let event = notification.userInfo?[
          NSPersistentCloudKitContainer.eventNotificationUserInfoKey
        ] as? NSPersistentCloudKitContainer.Event
      else { return }

      let activity = Activity(
        kind: Self.name(for: event.type),
        started: event.startDate,
        ended: event.endDate,
        succeeded: event.succeeded,
        errorDescription: event.error?.localizedDescription
      )
      let type = event.type

      MainActor.assumeIsolated {
        self?.record(activity, of: type)
      }
    }
  }

  private func record(_ activity: Activity, of type: NSPersistentCloudKitContainer.EventType) {
    switch type {
    case .setup: lastSetup = activity
    case .import: lastImport = activity
    case .export: lastExport = activity
    @unknown default: break
    }

    if let errorDescription = activity.errorDescription {
      logger.error(
        "CloudKit \(activity.kind, privacy: .public) failed: \(errorDescription, privacy: .public)")
    }
  }

  private nonisolated static func name(for type: NSPersistentCloudKitContainer.EventType) -> String {
    switch type {
    case .setup: "Setup"
    case .import: "Download"
    case .export: "Upload"
    @unknown default: "Activity"
    }
  }
}
