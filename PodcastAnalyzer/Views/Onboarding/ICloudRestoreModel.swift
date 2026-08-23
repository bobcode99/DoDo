//
//  ICloudRestoreModel.swift
//  PodcastAnalyzer
//
//  Drives the onboarding restore: pulls the synced subscription list and
//  imports every feed, exposing just enough state for the page to render.
//

#if os(iOS)
import Foundation

@MainActor
@Observable
final class ICloudRestoreModel {
  private(set) var isRestoring = true
  private(set) var restoredCount = 0

  func restore() async {
    let rssURLs = SubscriptionSyncCoordinator.shared.cloudSubscriptionRSSURLs()
    restoredCount = rssURLs.count
    await PodcastImportManager.shared.importPodcasts(from: rssURLs)
    // Suppress the import sheet this triggers — the restore page has its own
    // progress UI, and the sheet's presentation context is the base
    // ContentView underneath the onboarding fullScreenCover.
    PodcastImportManager.shared.dismissImportSheet()
    isRestoring = false
  }
}

#endif
