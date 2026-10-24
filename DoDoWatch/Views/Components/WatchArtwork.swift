//
//  WatchArtwork.swift
//  DoDoWatch
//
//  Podcast artwork, rounded and square.
//
//  Uses SwiftUI's own AsyncImage rather than Nuke, which the phone uses: the
//  watch draws a handful of thumbnails per screen, and AsyncImage's URLCache
//  backing (HTTP-cached by default from watchOS 27) is enough for that. Worth revisiting only if scrolling shows a
//  re-fetch — Pocket Casts eventually needed a 30 MB capped image cache on
//  watch, but they were rendering far more per screen than this.
//

import SwiftUI

struct WatchArtwork: View {
  let urlString: String
  var size: CGFloat = 40

  var body: some View {
    Group {
      if #available(watchOS 27, *) {
        // Cached art first, no revalidation: the default protocol policy asks
        // the server again once headers expire, and a watch listening to
        // downloads is often offline — the art went blank exactly then.
        AsyncImage(
          request: URL(string: urlString).map { URLRequest(url: $0, cachePolicy: .returnCacheDataElseLoad) },
          content: artwork
        )
      } else {
        AsyncImage(url: URL(string: urlString), content: artwork)
      }
    }
    .frame(width: size, height: size)
    .clipShape(.rect(cornerRadius: size * 0.22))
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func artwork(_ phase: AsyncImagePhase) -> some View {
    switch phase {
    case .success(let image):
      image.resizable().scaledToFill()
    default:
      Rectangle().fill(.quaternary)
    }
  }
}
