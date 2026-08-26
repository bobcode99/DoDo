//
//  NotificationSummaryTests.swift
//  PodcastAnalyzerTests
//
//  The expanded new-episode notification shows the feed's episode description,
//  which arrives as HTML. Stripping it has to survive tags, entities and long
//  show notes without leaking markup into the banner.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@MainActor
struct NotificationSummaryTests {
  @Test func stripsTagsAndEntities() {
    let raw = "<p>Guest &amp; host talk <b>shop</b>.</p>\n<a href=\"x\">Links</a>"
    #expect(BackgroundSyncManager.plainSummary(raw) == "Guest & host talk shop. Links")
  }

  @Test func returnsNilForEmptyOrMarkupOnly() {
    #expect(BackgroundSyncManager.plainSummary(nil) == nil)
    #expect(BackgroundSyncManager.plainSummary("<br/><p> </p>") == nil)
  }

  @Test func truncatesWithEllipsis() {
    let summary = BackgroundSyncManager.plainSummary(String(repeating: "a", count: 600))
    #expect(summary?.count == 401)
    #expect(summary?.hasSuffix("\u{2026}") == true)
  }
}
