//
//  CachedAsyncImage.swift
//  PodcastAnalyzer
//
//  Thin wrappers around Nuke's LazyImage for cached image loading.
//

import SwiftUI
import NukeUI
import Nuke

// MARK: - Pipeline Configuration

/// Call once at app launch to configure Nuke's image pipeline with a persistent data cache.
func configureImagePipeline() {
  var config = ImagePipeline.Configuration()

  if let dataCache = try? DataCache(name: "com.podcast.analyzer.images") {
    dataCache.sizeLimit = 200 * 1024 * 1024
    config.dataCache = dataCache
  }

  // `.storeAll` persists both the original bytes *and* the encoded resized
  // variant (CachedArtworkImage adds a Resize processor). With the default
  // `.automatic` policy the processed thumbnail wasn't always rehydrated on
  // cold launch — every grid cell would re-decode from the original, so the
  // Library tab visibly re-loaded its artwork on every relaunch.
  config.dataCachePolicy = .storeAll

  let imageCache = ImageCache()
  #if os(macOS)
  imageCache.costLimit = 80 * 1024 * 1024
  imageCache.countLimit = 200
  #else
  imageCache.costLimit = 120 * 1024 * 1024
  imageCache.countLimit = 300
  #endif
  config.imageCache = imageCache

  ImagePipeline.shared = ImagePipeline(configuration: config)
}

// MARK: - Cached Async Image View

/// Drop-in replacement for the previous custom CachedAsyncImage, backed by Nuke.
nonisolated struct CachedAsyncImage<Content: View, Placeholder: View>: View {
  let url: URL?
  @ViewBuilder let content: (Image) -> Content
  @ViewBuilder let placeholder: () -> Placeholder

  init(
    url: URL?,
    @ViewBuilder content: @escaping (Image) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    self.url = url
    self.content = content
    self.placeholder = placeholder
  }

  var body: some View {
    LazyImage(url: url) { state in
      if let image = state.image {
        content(image)
      } else {
        placeholder()
      }
    }
  }
}

// MARK: - Convenience Initializers

extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView> {
  init(
    url: URL?,
    @ViewBuilder content: @escaping (Image) -> Content
  ) {
    self.init(url: url, content: content, placeholder: { ProgressView() })
  }
}

extension CachedAsyncImage where Content == Image, Placeholder == ProgressView<EmptyView, EmptyView> {
  init(url: URL?) {
    self.init(url: url, content: { $0 }, placeholder: { ProgressView() })
  }
}

// MARK: - Apple Artwork URL Upgrade

/// Rewrites Apple iTunes/mzstatic artwork URLs to a higher resolution.
///
/// Apple serves podcast artwork at `https://.../{N}x{N}bb.{ext}`; the source
/// image is the same regardless of the requested size, so requesting a larger
/// path gives back a sharper image. For non-Apple URLs the string is returned
/// unchanged.
nonisolated enum AppleArtworkURL {
  /// Cap on the rewritten dimension. Apple's CDN typically serves up to ~3000px.
  static let maxDimension = 1200

  /// Returns the URL string rewritten to `targetPixels x targetPixels` if the
  /// URL matches the Apple `{N}x{N}bb` pattern. Caps the result at `maxDimension`.
  static func upgrade(_ urlString: String, targetPixels: Int) -> String {
    let clamped = min(max(targetPixels, 100), maxDimension)
    guard let regex = try? NSRegularExpression(pattern: "[0-9]{2,4}x[0-9]{2,4}bb") else {
      return urlString
    }
    let range = NSRange(urlString.startIndex..., in: urlString)
    return regex.stringByReplacingMatches(
      in: urlString,
      range: range,
      withTemplate: "\(clamped)x\(clamped)bb"
    )
  }
}

// MARK: - Cached Artwork Image (Specialized for Podcasts)

nonisolated struct CachedArtworkImage: View {
  let urlString: String?
  let size: CGFloat
  let cornerRadius: CGFloat

  init(urlString: String?, size: CGFloat = 60, cornerRadius: CGFloat = 8) {
    self.urlString = urlString
    self.size = size
    self.cornerRadius = cornerRadius
  }

  /// Target pixel dimension for the source image — aim for @3x quality so
  /// retina displays get a sharp result after Nuke downsamples.
  private var targetPixels: Int { Int(size * 3) }

  private var url: URL? {
    guard let urlString else { return nil }
    return URL(string: AppleArtworkURL.upgrade(urlString, targetPixels: targetPixels))
  }

  private var request: ImageRequest? {
    guard let url else { return nil }
    var request = ImageRequest(url: url)
    request.processors = [
      ImageProcessors.Resize(
        size: CGSize(width: size, height: size),
        unit: .points,
        contentMode: .aspectFill,
        crop: true,
        upscale: false
      )
    ]
    return request
  }

  var body: some View {
    LazyImage(request: request) { state in
      if let image = state.image {
        image.resizable().aspectRatio(contentMode: .fill)
      } else {
        Color.gray.opacity(0.2)
          .overlay(ProgressView().scaleEffect(0.5))
      }
    }
    .frame(width: size, height: size)
    .clipShape(.rect(cornerRadius: cornerRadius))
    .clipped()
  }
}

// MARK: - Cache Utilities

/// Convenience for clearing and inspecting Nuke's image caches.
nonisolated enum ImageCacheUtility {
  static func clearAllCache() {
    ImagePipeline.shared.cache.removeAll()
  }

  /// Returns the total size of the data cache in bytes, or 0 if unavailable.
  static func dataCacheTotalSize() -> Int64 {
    if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
      return Int64(dataCache.totalSize)
    }
    return 0
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: 20) {
    CachedArtworkImage(
      urlString: "https://example.com/image.jpg",
      size: 100,
      cornerRadius: 12
    )

    CachedAsyncImage(url: URL(string: "https://example.com/test.jpg")) { image in
      image
        .resizable()
        .scaledToFit()
    } placeholder: {
      Color.gray
    }
    .frame(width: 200, height: 200)
  }
}
