//
//  SharedPodcastLink.swift
//  PodcastAnalyzer
//
//  What a link handed over by the "Open in DoDo" share extension points at.
//  The extension shows up for any web URL — its activation rule can filter by
//  type, not by site — so most of what arrives is not a podcast at all.
//

import Foundation

nonisolated enum SharedPodcastLink: Equatable {
  /// …/podcast/<name>/id<podcastID>?i=<episodeID>
  case episode(podcastID: Int, episodeID: Int)
  /// …/podcast/<name>/id<podcastID>, no episode.
  case show(podcastID: Int)
  case unsupported

  init(_ link: String) {
    guard let url = URL(string: link),
          let host = url.host(), host == "apple.com" || host.hasSuffix(".apple.com"),
          let idComponent = url.pathComponents.last(where: { $0.hasPrefix("id") }),
          let podcastID = Int(idComponent.dropFirst(2))
    else {
      self = .unsupported
      return
    }
    let episodeID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "i" })?.value
      .flatMap { Int($0) }
    self = episodeID.map { .episode(podcastID: podcastID, episodeID: $0) } ?? .show(podcastID: podcastID)
  }
}
