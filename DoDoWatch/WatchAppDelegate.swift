//
//  WatchAppDelegate.swift
//  DoDoWatch
//
//  Background wake-ups. Two reasons the system launches us:
//
//  1. A background URLSession finished a download. Without routing that task
//     into the session and holding it open, a download that completed while the
//     app was suspended is reported to nobody.
//  2. Our own scheduled refresh, which gives CoreData+CloudKit a chance to pull
//     changes down.
//
//  The refresh re-arm is lifted from Pocket Casts
//  (UI/ExtensionDelegate.swift:107-118) — 60 minutes, re-scheduled both on
//  activate and on each fire, since watchOS only ever honours one pending
//  request. They need it because their watch has no push at all; we need it
//  because CloudKit's push is best-effort and a watch is asleep most of the
//  time. Belt and braces either way.
//

import SwiftUI
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
  /// Matches Pocket Casts' interval. Long on purpose: watchOS grants these
  /// sparingly, and asking too often gets the app deprioritised rather than
  /// refreshed more.
  private static let refreshInterval: TimeInterval = 60 * 60

  func applicationDidBecomeActive() {
    scheduleNextRefresh()
  }

  func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    for task in backgroundTasks {
      switch task {
      case let refreshTask as WKApplicationRefreshBackgroundTask:
        // Being awake is the point: the CloudKit mirror imports on its own once
        // the store is live, so there is nothing to call here.
        scheduleNextRefresh()
        refreshTask.setTaskCompletedWithSnapshot(false)

      case let sessionTask as WKURLSessionRefreshBackgroundTask:
        WatchDownloadManager.shared.handle(sessionTask)

      case let snapshotTask as WKSnapshotRefreshBackgroundTask:
        snapshotTask.setTaskCompleted(
          restoredDefaultState: true,
          estimatedSnapshotExpiration: .distantFuture,
          userInfo: nil
        )

      case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
        // The phone pushed state while we were asleep; WatchSessionManager has
        // already taken it from the delegate callback.
        connectivityTask.setTaskCompletedWithSnapshot(true)

      default:
        // Completing immediately keeps watchOS from counting the app as
        // unresponsive.
        task.setTaskCompletedWithSnapshot(false)
      }
    }
  }

  private func scheduleNextRefresh() {
    WKApplication.shared().scheduleBackgroundRefresh(
      withPreferredDate: Date(timeIntervalSinceNow: Self.refreshInterval),
      userInfo: nil
    ) { _ in
      // Nothing to do on failure — the next activate re-arms it anyway.
    }
  }
}
