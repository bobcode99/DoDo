//
//  WatchAppDelegate.swift
//  DoDoWatch
//
//  watchOS relaunches the app in the background when a background URLSession
//  has events to hand back. Without routing that task into the session and
//  holding it open, a download that completed while the app was suspended is
//  reported to nobody.
//

import SwiftUI
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
  func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
    for task in backgroundTasks {
      switch task {
      case let sessionTask as WKURLSessionRefreshBackgroundTask:
        WatchDownloadManager.shared.handle(sessionTask)
      default:
        // Nothing scheduled yet — completing immediately keeps watchOS from
        // counting the app as unresponsive.
        task.setTaskCompletedWithSnapshot(false)
      }
    }
  }
}
