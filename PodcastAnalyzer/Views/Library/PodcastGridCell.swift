//
//  PodcastGridCell.swift
//  PodcastAnalyzer
//
//  One artwork tile in the Library podcast grid.
//

import Nuke
import NukeUI
import SwiftUI

struct PodcastGridCell: View {
  let item: PodcastGridItem

  private var latestEpisodeDate: String? {
    guard let date = item.latestEpisodeDate else { return nil }
    return Formatters.formatRelativeDate(date, locale: Formatters.appLocale)
  }

  /// Downsample to a grid-cell-sized thumbnail instead of decoding the full-res
  /// CDN artwork (up to ~3000px) into memory per cell — that full decode was the
  /// scroll/cold-load lag. ~200pt @3x ≈ 600px, sharp for a half-screen cell.
  private var request: ImageRequest? {
    guard !item.imageURL.isEmpty,
          let url = URL(string: AppleArtworkURL.upgrade(item.imageURL, targetPixels: 600))
    else { return nil }
    var request = ImageRequest(url: url)
    request.processors = [
      ImageProcessors.Resize(
        size: CGSize(width: 200, height: 200),
        unit: .points,
        contentMode: .aspectFill,
        crop: true,
        upscale: false
      )
    ]
    return request
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      LazyImage(request: request) { state in
        if let image = state.image {
          image.resizable().aspectRatio(contentMode: .fill)
        } else {
          Color.gray.opacity(0.2)
            .overlay(ProgressView().scaleEffect(0.5))
        }
      }
      .aspectRatio(1, contentMode: .fit)
      .clipShape(.rect(cornerRadius: 10))
      .clipped()

      Text(item.title)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2, reservesSpace: true)
        .foregroundStyle(.primary)

      // Reserves the date row's height even when a podcast has no episodes
      // yet, so every cell in a grid row bottoms out at the same height
      // instead of the shorter ones leaving a gap under the artwork.
      Text(latestEpisodeDate ?? " ")
        .font(.caption)
        .foregroundStyle(.secondary)
        .opacity(latestEpisodeDate == nil ? 0 : 1)
    }
  }
}
