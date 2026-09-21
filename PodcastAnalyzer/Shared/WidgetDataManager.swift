//
//  WidgetDataManager.swift
//  PodcastAnalyzer
//
//  Moves playback state between the main app and the widget over App Group
//  UserDefaults. The payload itself is `WidgetPlaybackData` in SharedCore/,
//  which the watch target sends over WatchConnectivity — App Groups are
//  same-device only and never reach the watch.
//

import Foundation
import Nuke
import WidgetKit

#if os(iOS)
import UIKit
private typealias WidgetImage = UIImage
#else
import AppKit
private typealias WidgetImage = NSImage
#endif

// MARK: - Widget Data Manager

/// Manages reading/writing widget data via App Group UserDefaults
nonisolated enum WidgetDataManager {
  /// App Group identifier - must match the App Group configured in Xcode
  static let appGroupIdentifier = "group.com.jn.PodcastAnalyzer"

  /// Key for storing playback data in UserDefaults
  private static let playbackDataKey = "widgetPlaybackData"

  /// Shared UserDefaults for App Group
  static var sharedDefaults: UserDefaults? {
    UserDefaults(suiteName: appGroupIdentifier)
  }

  /// Write playback data to shared UserDefaults (called from main app)
  static func writePlaybackData(_ data: WidgetPlaybackData) {
    guard let defaults = sharedDefaults else { return }

    do {
      let encoded = try JSONEncoder().encode(data)
      defaults.set(encoded, forKey: playbackDataKey)
      // Force flush to disk so the widget extension (separate process) reads fresh data
      defaults.synchronize()
    } catch {
      // Silently fail - widget will show placeholder
    }
  }

  /// Read playback data from shared UserDefaults (called from widget)
  static func readPlaybackData() -> WidgetPlaybackData? {
    guard let defaults = sharedDefaults,
          let data = defaults.data(forKey: playbackDataKey) else {
      return nil
    }

    do {
      return try JSONDecoder().decode(WidgetPlaybackData.self, from: data)
    } catch {
      return nil
    }
  }

  /// Clear playback data (called when playback stops)
  static func clearPlaybackData() {
    sharedDefaults?.removeObject(forKey: playbackDataKey)
  }

  /// Check if playback data is stale (more than 24 hours old)
  static func isDataStale(_ data: WidgetPlaybackData) -> Bool {
    Date().timeIntervalSince(data.lastUpdated) > 86400
  }

  // MARK: - Artwork Image File (shared container)

  /// URL for the shared App Group container directory
  private static var sharedContainerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
  }

  /// File URL for the cached widget artwork image
  static var artworkFileURL: URL? {
    sharedContainerURL?.appending(path: "widget_artwork.jpg")
  }

  /// The `imageURL` whose artwork the shared file currently holds. The widget
  /// draws the file only when this matches its entry's `imageURL`. It used to
  /// draw whatever file was there, so while a download was in flight — or
  /// after it failed, or for an episode with no artwork — the widget paired
  /// the new episode's title with the previous show's cover.
  static let artworkSourceKey = "widgetArtworkSourceURL"

  @MainActor private static var pendingArtworkURL: String?

  /// Download (or read from Nuke's disk cache — works offline for art the app
  /// has shown) the artwork for `imageURLString` and hand it to the widget.
  @MainActor static func cacheArtworkIfNeeded(from imageURLString: String?) {
    guard let imageURLString, imageURLString != pendingArtworkURL,
          sharedDefaults?.string(forKey: artworkSourceKey) != imageURLString,
          let url = URL(string: AppleArtworkURL.canonical(imageURLString)) else { return }
    pendingArtworkURL = imageURLString
    // 300pt fit keeps the file under WidgetKit's ~2.27M px² image limit at any
    // scale; Nuke downsamples while decoding instead of a second resize pass.
    let request = ImageRequest(url: url, processors: [
      ImageProcessors.Resize(
        size: CGSize(width: 300, height: 300), unit: .points,
        contentMode: .aspectFit, crop: false, upscale: false)
    ])
    Task.detached(priority: .utility) {
      let jpeg = (try? await ImagePipeline.shared.image(for: request)).flatMap(jpegData)
      await MainActor.run {
        // A newer episode started while this loaded — its request owns the file now.
        guard pendingArtworkURL == imageURLString else { return }
        // Cleared on failure too, so the next play/pause retries.
        pendingArtworkURL = nil
        guard let jpeg, let fileURL = artworkFileURL else { return }
        sharedDefaults?.removeObject(forKey: artworkSourceKey)
        guard (try? jpeg.write(to: fileURL, options: .atomic)) != nil else { return }
        sharedDefaults?.set(imageURLString, forKey: artworkSourceKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
      }
    }
  }

  private static func jpegData(_ image: WidgetImage) -> Data? {
    #if os(iOS)
    image.jpegData(compressionQuality: 0.85)
    #else
    image.tiffRepresentation
      .flatMap(NSBitmapImageRep.init(data:))?
      .representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    #endif
  }
}
