//
//  PodcastHeroHeader.swift
//  PodcastAnalyzer
//
//  Show header for EpisodeListView — the "immersive hero" appearance: a
//  gradient tinted from the artwork that bleeds into the episode list, with
//  the primary action ("Latest") promoted out of the ••• menu.
//

import CoreGraphics
import ImageIO
import Nuke
import SwiftUI

// MARK: - Artwork tint

/// Average colour of a podcast's artwork, cached per URL for the session.
/// Purely cosmetic — every caller renders a neutral gradient until it resolves,
/// so a failure here is invisible rather than an error state.
@MainActor
enum ArtworkTint {
  private static var cache: [String: Color] = [:]

  static func cached(for urlString: String) -> Color? { cache[urlString] }

  static func resolve(for urlString: String) async -> Color? {
    if let hit = cache[urlString] { return hit }
    // 100px is far more than an average needs, and it is a size Nuke has
    // usually already fetched for the artwork itself.
    guard let url = URL(string: AppleArtworkURL.upgrade(urlString, targetPixels: 100)),
      let (data, _) = try? await ImagePipeline.shared.data(for: ImageRequest(url: url)),
      let color = saturationWeightedAverage(of: data)
    else { return nil }
    cache[urlString] = color
    return color
  }
}

/// Saturation-weighted mean of a 32×32 thumbnail. A flat mean turns almost
/// every cover into the same muddy grey; weighting each pixel by its channel
/// spread keeps the colour the artwork actually reads as.
private nonisolated func saturationWeightedAverage(of data: Data) -> Color? {
  let side = 32
  guard let source = CGImageSourceCreateWithData(data as CFData, nil),
    let thumbnail = CGImageSourceCreateThumbnailAtIndex(
      source, 0,
      [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: side,
      ] as CFDictionary)
  else { return nil }

  var pixels = [UInt8](repeating: 0, count: side * side * 4)
  let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
    guard
      let context = CGContext(
        data: buffer.baseAddress,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return false }
    context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: side, height: side))
    return true
  }
  guard drew else { return nil }

  var red = 0.0, green = 0.0, blue = 0.0, weightSum = 0.0
  for index in stride(from: 0, to: pixels.count, by: 4) {
    let r = Double(pixels[index]) / 255
    let g = Double(pixels[index + 1]) / 255
    let b = Double(pixels[index + 2]) / 255
    // Floor so a fully greyscale cover still averages to itself.
    let weight = 0.12 + (max(r, g, b) - min(r, g, b))
    red += r * weight
    green += g * weight
    blue += b * weight
    weightSum += weight
  }
  guard weightSum > 0 else { return nil }

  // Covers range from near-black photography to blown-out white, and both
  // average to something that cannot carry white text. Scale the result into a
  // mid band — this keeps the hue and the relative channel mix, and only moves
  // the level.
  var r = red / weightSum, g = green / weightSum, b = blue / weightSum
  let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
  if luminance > 0.001 {
    let scale = min(max(luminance, 0.28), 0.55) / luminance
    r = min(r * scale, 1)
    g = min(g * scale, 1)
    b = min(b * scale, 1)
  }
  return Color(.sRGB, red: r, green: g, blue: b)
}

// MARK: - Hero header

struct PodcastHeroHeader<Description: View>: View {
  let artworkURL: String
  let title: String
  /// Shown first on the meta line. Empty when the feed carries no author.
  let artist: String
  let episodeCount: Int
  let language: String
  let isSubscribed: Bool
  /// Distance to extend the tint *above* this view, so the fill reaches the
  /// back/••• row instead of starting under it.
  ///
  /// Passed in rather than taken from `.ignoresSafeArea`: inside a `List` the
  /// safe area is already spent as content inset, so a row has none left to
  /// expand into. The host measures it and we bleed upward by hand.
  var topBleed: CGFloat = 0
  /// "Resume" when the host resolved an episode the user was part-way through,
  /// "Latest" when it fell back to the newest one.
  var playTitle: String = "Latest"
  let canPlay: Bool
  let onPlay: () -> Void
  let onToggleSubscribe: () -> Void
  @ViewBuilder let description: () -> Description

  @State private var tint: Color?

  /// Neutral stand-in until the artwork average resolves, and the permanent
  /// value when it cannot be computed.
  private var base: Color { tint ?? Color(.sRGB, red: 0.29, green: 0.33, blue: 0.59) }
  private var deep: Color { base.mix(with: .black, by: 0.45) }
  private var mid: Color { base.mix(with: .black, by: 0.22) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      artworkAndTitle
      actionButtons
      description()
        .padding(.top, 16)
    }
    .padding(.horizontal, 20)
    .padding(.top, 4)
    .padding(.bottom, 12)
    .background(alignment: .top) {
      // Fades to clear rather than to a background colour so the tint bleeds
      // into whatever the list is drawn on, in either colour scheme.
      LinearGradient(
        stops: [
          .init(color: deep, location: 0),
          .init(color: mid, location: 0.55),
          .init(color: mid.opacity(0), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea(edges: .top)
    }
    .background(alignment: .top) {
      // Solid rather than a continuation of the gradient: this strip sits above
      // the gradient's first stop, which is `deep` anyway, so the two meet with
      // no seam. Scrolls away with the header because it is part of the row.
      deep
        .frame(height: topBleed)
        .padding(.top, -topBleed)
    }
    .task(id: artworkURL) {
      if let hit = ArtworkTint.cached(for: artworkURL) {
        tint = hit
      } else {
        tint = await ArtworkTint.resolve(for: artworkURL)
      }
    }
  }

  private var artworkAndTitle: some View {
    // Centered against the artwork rather than bottom-aligned. Bottom alignment
    // was set when the text column was three lines tall and filled the cover;
    // with the author folded into the meta line it is two, and sat in the
    // artwork's lower corner with the top half empty.
    HStack(alignment: .center, spacing: 15) {
      CachedArtworkImage(urlString: artworkURL, size: 106, cornerRadius: 18)
        .shadow(color: .black.opacity(0.34), radius: 13, y: 6)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.title3)
          .fontWeight(.bold)
          .foregroundStyle(.white)
          .lineLimit(2)

        metaText
          .font(.caption)
          .foregroundStyle(.white.opacity(0.7))
          .lineLimit(2)
      }
    }
  }

  /// Author · episode count · language, on one line.
  ///
  /// `Text`, not an interpolated `String` — the in-app language picker works by
  /// overriding the environment locale, which only `Text` honours. The author is
  /// concatenated rather than interpolated so the two count strings keep the
  /// keys they are already translated under.
  private var metaText: Text {
    if artist.isEmpty {
      if language.isEmpty {
        return Text("\(episodeCount) episodes")
      } else {
        return Text("\(episodeCount) episodes · \(language)")
      }
    } else {
      if language.isEmpty {
        return Text("\(artist) · \(episodeCount) episodes")
      } else {
        return Text("\(artist) · \(episodeCount) episodes · \(language)")
      }
    }
  }

  private var actionButtons: some View {
    HStack(spacing: 9) {
      Button(action: onPlay) {
        HStack(spacing: 7) {
          Image(systemName: "play.fill")
            .font(.system(size: 13))
          Text(playTitle)
            .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(deep)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(.white, in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
      }
      .buttonStyle(.plain)
      .disabled(!canPlay)
      .opacity(canPlay ? 1 : 0.5)

      Button(action: onToggleSubscribe) {
        Text(isSubscribed ? "Following" : "Follow")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 18)
          .frame(minHeight: 42)
          .background(.white.opacity(0.24), in: .rect(cornerRadius: 12))
      }
      .buttonStyle(.plain)
    }
    .padding(.top, 18)
  }
}
