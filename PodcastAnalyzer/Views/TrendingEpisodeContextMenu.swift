//
//  TrendingEpisodeContextMenu.swift
//  PodcastAnalyzer
//
//  Created by JunNianLo on 2026/5/16.
//


import NukeUI
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TrendingEpisodeContextMenu: View {
  let episode: ApplePodcastService.TrendingEpisode

  var body: some View {
    // Go to Show
    NavigationLink(value: episode.asAppleRSSPodcast) {
      Label("Go to Show", systemImage: "square.stack")
    }

    Divider()

    // Copy episode name
    Button {
      PlatformClipboard.string = episode.episode.trackName
    } label: {
      Label("Copy Episode Name", systemImage: "doc.on.doc")
    }

    // Share
    if let urlString = episode.episode.trackViewUrl, let url = URL(string: urlString) {
      Button {
        PlatformShareSheet.share(url: url)
      } label: {
        Label("Share Episode", systemImage: "square.and.arrow.up")
      }
    } else if let urlString = episode.episode.episodeUrl, let url = URL(string: urlString) {
      Button {
        PlatformShareSheet.share(url: url)
      } label: {
        Label("Share Episode", systemImage: "square.and.arrow.up")
      }
    }
  }
}