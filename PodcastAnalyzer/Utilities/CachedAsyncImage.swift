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
  // `withDataCache` also turns off the loader's URLCache. The plain
  // `Configuration()` kept Nuke's 150 MB HTTP cache *and* this DataCache, so
  // every image was written to disk twice. Same cache name keeps what's stored.
  var config = ImagePipeline.Configuration.withDataCache(
    name: "com.podcast.analyzer.images",
    sizeLimit: 200 * 1024 * 1024
  )

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

/// Normalizes Apple iTunes/mzstatic artwork URLs to one source size.
///
/// Apple serves podcast artwork at `https://.../{N}x{N}bb.{ext}` and renders
/// any `N` from the same master. Every artwork request goes through
/// `canonical(_:)` so a cover has exactly one URL — and one disk-cache entry —
/// app-wide. Views downsample locally (Nuke `Resize`). Asking for `size * 3`
/// per view gave each screen its own URL, so art cached by the list was a miss
/// on the detail sheet: blank artwork offline. Non-Apple URLs pass through.
nonisolated enum AppleArtworkURL {
  /// Largest tile is 200pt @3x. ponytail: one size for all; add a second
  /// bucket only if a bigger view looks soft (it will miss offline until seen).
  static let pixels = 600

  static func canonical(_ urlString: String) -> String {
    urlString.replacing(#/[0-9]{2,4}x[0-9]{2,4}bb/#, with: "\(pixels)x\(pixels)bb")
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

  private var url: URL? {
    guard let urlString else { return nil }
    return URL(string: AppleArtworkURL.canonical(urlString))
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
        // Spinner only while a load is in flight — offline, a failed load
        // used to spin forever.
        Color.gray.opacity(0.2)
          .overlay { if state.isLoading { ProgressView().scaleEffect(0.5) } }
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
