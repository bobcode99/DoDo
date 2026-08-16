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

  /// Write artwork image data to the shared container (called from main app)
  static func writeArtworkData(_ data: Data) {
    guard let fileURL = artworkFileURL else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  /// Read artwork image data from the shared container (called from widget)
  static func readArtworkData() -> Data? {
    guard let fileURL = artworkFileURL else { return nil }
    return try? Data(contentsOf: fileURL)
  }

  /// Clear the cached artwork file
  static func clearArtwork() {
    guard let fileURL = artworkFileURL else { return }
    try? FileManager.default.removeItem(at: fileURL)
  }

  /// Download and cache artwork image from URL using Nuke.
  /// Skips download if the same URL was already cached.
  /// Called from @MainActor context (EnhancedAudioManager).
  /// Resize an image to at most 300×300 points so it stays within WidgetKit's
  /// pixel-area limit (~2,275,490 px²). Images already smaller are returned as-is.
  private static func resizedForWidget(_ image: WidgetImage) -> WidgetImage {
    let maxDimension: CGFloat = 300
    let size = image.size
    guard size.width > maxDimension || size.height > maxDimension else { return image }
    let scale = min(maxDimension / size.width, maxDimension / size.height)
    let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    #if os(iOS)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    #else
    let resized = NSImage(size: newSize)
    resized.lockFocus()
    image.draw(in: CGRect(origin: .zero, size: newSize))
    resized.unlockFocus()
    return resized
    #endif
  }

  @MainActor private static var lastCachedArtworkURL: String?

  @MainActor static func cacheArtworkIfNeeded(from imageURLString: String?) {
    guard let imageURLString, imageURLString != lastCachedArtworkURL,
          let imageURL = URL(string: imageURLString) else {
      return
    }
    lastCachedArtworkURL = imageURLString
    Task.detached(priority: .utility) {
      do {
        let image = try await ImagePipeline.shared.image(for: imageURL)
        // WidgetKit rejects images whose pixel area exceeds ~2,275,490 px²
        // (roughly 1508×1508). Resize to 300×300 pt — enough for any widget
        // size at 3× scale — before saving to the shared container.
        let widgetImage = Self.resizedForWidget(image)
        #if os(iOS)
        if let jpegData = widgetImage.jpegData(compressionQuality: 0.85) {
          writeArtworkData(jpegData)
          // Trigger a second reload now that the artwork file is on disk.
          await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
          }
        }
        #else
        if let tiffData = widgetImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
          writeArtworkData(jpegData)
          await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: "NowPlayingWidget")
          }
        }
        #endif
      } catch {
        // Image download failed — widget will show placeholder
      }
    }
  }
}
