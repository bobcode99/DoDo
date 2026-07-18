//
//  SubscriptionSyncCoordinatorTests.swift
//  PodcastAnalyzerTests
//
//  Verifies the CloudKit-synced subscription pointer: subscribing/
//  unsubscribing upserts/deletes SubscribedPodcastModel, and onboarding's
//  "returning user" detection reads it correctly. Runs entirely against a
//  single in-memory SwiftData container (a brand-new @Model type was
//  observed to crash the SwiftData runtime on this OS build when many
//  separate in-memory containers for it were created back-to-back in one
//  process — see TranscriptStoreTests — so this suite uses one container
//  for every assertion instead of one per test).
//

import Foundation
import SwiftData
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Subscription sync")
struct SubscriptionSyncCoordinatorTests {

    @Test("Subscribing upserts a CloudKit row; unsubscribing removes it; detection reflects both")
    func subscribeAndUnsubscribeLifecycle() throws {
        let schema = Schema([SubscribedPodcastModel.self, PodcastInfoModel.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let coordinator = SubscriptionSyncCoordinator()
        coordinator.setModelContainer(container)

        let podcastInfo = PodcastInfo(
            title: "My Show",
            description: nil,
            episodes: [],
            rssUrl: "https://example.com/feed.xml",
            imageURL: "",
            language: "en"
        )
        let podcast = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date(), isSubscribed: true)

        // Not yet pushed — sync() must be called explicitly (mirrors the
        // model's own didSet, which only fires on later assignment, not init).
        #expect(!coordinator.hasCloudSubscriptions())

        coordinator.sync(from: podcast)
        #expect(coordinator.hasCloudSubscriptions())
        #expect(coordinator.cloudSubscriptionRSSURLs() == ["https://example.com/feed.xml"])

        podcast.isSubscribed = false
        coordinator.sync(from: podcast)
        #expect(!coordinator.hasCloudSubscriptions())
        #expect(coordinator.cloudSubscriptionRSSURLs().isEmpty)
    }

    @Test("Multiple subscriptions all appear in cloudSubscriptionRSSURLs()")
    func multipleSubscriptions() throws {
        let schema = Schema([SubscribedPodcastModel.self, PodcastInfoModel.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let coordinator = SubscriptionSyncCoordinator()
        coordinator.setModelContainer(container)

        for i in 0..<3 {
            let info = PodcastInfo(
                title: "Show \(i)", description: nil, episodes: [],
                rssUrl: "https://example.com/feed\(i).xml", imageURL: "", language: "en"
            )
            let podcast = PodcastInfoModel(podcastInfo: info, lastUpdated: Date(), isSubscribed: true)
            coordinator.sync(from: podcast)
        }

        #expect(Set(coordinator.cloudSubscriptionRSSURLs()) == [
            "https://example.com/feed0.xml",
            "https://example.com/feed1.xml",
            "https://example.com/feed2.xml",
        ])
    }
}
