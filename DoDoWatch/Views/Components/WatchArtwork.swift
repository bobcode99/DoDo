//
//  WatchArtwork.swift
//  DoDoWatch
//
//  Podcast artwork, rounded and square.
//
//  Uses SwiftUI's own AsyncImage rather than Nuke, which the phone uses: the
//  watch draws a handful of thumbnails per screen, and AsyncImage's URLCache
//  backing is enough for that. Worth revisiting only if scrolling shows a
//  re-fetch — Pocket Casts eventually needed a 30 MB capped image cache on
//  watch, but they were rendering far more per screen than this.
//

import SwiftUI

struct WatchArtwork: View {
  let urlString: String
  var size: CGFloat = 40

  var body: some View {
    AsyncImage(url: URL(string: urlString)) { phase in
      switch phase {
      case .success(let image):
        image.resizable().scaledToFill()
      default:
        Rectangle().fill(.quaternary)
      }
    }
    .frame(width: size, height: size)
    .clipShape(.rect(cornerRadius: size * 0.22))
  }
}
