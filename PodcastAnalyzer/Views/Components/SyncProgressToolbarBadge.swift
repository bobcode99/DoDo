//
//  SyncProgressToolbarBadge.swift
//  PodcastAnalyzer
//
//  Tiny toolbar badge showing background sync progress. Owns the
//  `BackgroundSyncManager` observation so sync progress ticks only invalidate
//  this leaf view instead of an entire screen body.
//

import SwiftUI

struct SyncProgressToolbarBadge: View {
  @State private var syncManager = BackgroundSyncManager.shared

  var body: some View {
    if syncManager.isSyncing {
      HStack(spacing: 6) {
        ProgressView().scaleEffect(0.7)
        if syncManager.syncProgressTotal > 0 {
          Text("\(syncManager.syncProgressCurrent)/\(syncManager.syncProgressTotal)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      .transition(.opacity)
    }
  }
}
