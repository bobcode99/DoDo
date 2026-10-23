//
//  SharedPodcastLinkTests.swift
//  PodcastAnalyzerTests
//
//  Links the "Open in DoDo" share extension can hand over.
//

import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Shared podcast link")
struct SharedPodcastLinkTests {

  @Test("An Apple Podcasts episode link yields both IDs")
  func episode() {
    let link = "https://podcasts.apple.com/tw/podcast/some-show/id1500839292?i=1000712345678"
    #expect(SharedPodcastLink(link) == .episode(podcastID: 1500839292, episodeID: 1000712345678))
  }

  @Test("Extra query items alongside ?i= don't matter")
  func episodeWithTracking() {
    let link = "https://podcasts.apple.com/us/podcast/x/id42?uo=4&i=7&l=en"
    #expect(SharedPodcastLink(link) == .episode(podcastID: 42, episodeID: 7))
  }

  @Test("A link without ?i= is the show, not an episode")
  func show() {
    #expect(SharedPodcastLink("https://podcasts.apple.com/us/podcast/x/id42") == .show(podcastID: 42))
  }

  @Test("A malformed episode ID falls back to the show")
  func badEpisodeID() {
    #expect(SharedPodcastLink("https://podcasts.apple.com/us/podcast/x/id42?i=abc") == .show(podcastID: 42))
  }

  @Test(
    "Anything that isn't an Apple Podcasts link is unsupported",
    arguments: [
      "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      "https://example.com/podcast/x/id42?i=7",  // right shape, wrong site
      "https://notapple.com/podcast/x/id42?i=7",  // suffix match must be on a dot
      "https://podcasts.apple.com/us/browse",
      "https://podcasts.apple.com/us/podcast/x/idABC",
      "not a url",
    ])
  func unsupported(link: String) {
    #expect(SharedPodcastLink(link) == .unsupported)
  }
}
