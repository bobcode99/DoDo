//
//  TestHostIsolationTests.swift
//  PodcastAnalyzerTests
//
//  The app that hosts these tests must not open its real stores: tests reach
//  the app's singletons, and a fake feed from one once landed in the
//  iCloud-synced subscriptions.
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Test host isolation")
struct TestHostIsolationTests {

    @Test("The host app knows it is hosting tests")
    func hostDetectsTests() {
        #expect(PodcastAnalyzerApp.isHostingTests)
    }

    @Test("The host app's stores live in memory and never sync to iCloud")
    func sharedContainerIsIsolated() throws {
        let container = try #require(AppIntentsModelStore.container, "the app wires this at launch")
        #expect(container.configurations.count == 2)
        for configuration in container.configurations {
            #expect(configuration.isStoredInMemoryOnly, "\(configuration.name) must not open the real store")
            #expect(configuration.cloudKitContainerIdentifier == nil, "\(configuration.name) must not sync to iCloud")
        }
    }
}
