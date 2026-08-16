//
//  PodcastRecencyOrderTests.swift
//  PodcastAnalyzerTests
//
//  The Library grid order. Both grids (iOS LibraryView, macOS
//  MacLibraryPodcastsView) sort through PodcastRecencyOrder, and the regression
//  this guards is a show publishing a new episode without moving to the front.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@Suite("Library podcast order")
struct PodcastRecencyOrderTests {
  private func sorted(_ shows: [(date: Date?, title: String)]) -> [String] {
    shows
      .sorted { PodcastRecencyOrder.isOrderedBefore($0.date, $0.title, $1.date, $1.title) }
      .map(\.title)
  }

  private static let day: TimeInterval = 86_400

  @Test("Newest episode first")
  func newestFirst() {
    let now = Date()
    let order = sorted([
      (now.addingTimeInterval(-3 * Self.day), "Old"),
      (now, "Fresh"),
      (now.addingTimeInterval(-Self.day), "Middle"),
    ])
    #expect(order == ["Fresh", "Middle", "Old"])
  }

  @Test("A new episode moves the show to the front")
  func newEpisodeJumpsToFront() {
    let now = Date()
    var shows: [(date: Date?, title: String)] = [
      (now, "Leader"),
      (now.addingTimeInterval(-5 * Self.day), "Laggard"),
    ]
    #expect(sorted(shows) == ["Leader", "Laggard"])

    // Laggard publishes.
    shows[1].date = now.addingTimeInterval(60)
    #expect(sorted(shows) == ["Laggard", "Leader"])
  }

  @Test("Undated feeds sink to the bottom")
  func undatedLast() {
    let now = Date()
    let order = sorted([
      (nil, "NoDates"),
      (now.addingTimeInterval(-10 * Self.day), "Ancient"),
    ])
    #expect(order == ["Ancient", "NoDates"])
  }

  @Test("Equal dates break on title, so the grid does not shuffle")
  func stableOnTies() {
    let now = Date()
    let input: [(date: Date?, title: String)] = [
      (now, "Zulu"), (now, "alpha"), (now, "Mike"),
    ]
    #expect(sorted(input) == ["alpha", "Mike", "Zulu"])
    // Same result from a different starting permutation.
    #expect(sorted(input.reversed().map { $0 }) == ["alpha", "Mike", "Zulu"])
  }
}
