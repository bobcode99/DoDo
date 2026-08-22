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

    @Test("A library subscribed before the synced store existed is backfilled on wiring")
    func backfillsPreexistingSubscriptions() throws {
        let schema = Schema([SubscribedPodcastModel.self, PodcastInfoModel.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        // Stand in for a real library: rows already subscribed, and never
        // pushed, because sync(from:) only fires on a state *change* and
        // setSubscribed(_:) returns early when the flag already matches.
        let context = container.mainContext
        for i in 0..<2 {
            let info = PodcastInfo(
                title: "Legacy \(i)", description: nil, episodes: [],
                rssUrl: "https://example.com/legacy\(i).xml", imageURL: "", language: "en"
            )
            context.insert(PodcastInfoModel(podcastInfo: info, lastUpdated: Date(), isSubscribed: true))
        }
        // An unsubscribed row must stay out of the mirror.
        let browsedInfo = PodcastInfo(
            title: "Browsed", description: nil, episodes: [],
            rssUrl: "https://example.com/browsed.xml", imageURL: "", language: "en"
        )
        context.insert(PodcastInfoModel(podcastInfo: browsedInfo, lastUpdated: Date(), isSubscribed: false))
        try context.save()

        let coordinator = SubscriptionSyncCoordinator()
        coordinator.setModelContainer(container)

        #expect(Set(coordinator.cloudSubscriptionRSSURLs()) == [
            "https://example.com/legacy0.xml",
            "https://example.com/legacy1.xml",
        ])

        // Idempotent: a second wiring must not duplicate rows.
        let second = SubscriptionSyncCoordinator()
        second.setModelContainer(container)
        #expect(second.cloudSubscriptionRSSURLs().count == 2)
    }

    @Test("A feed publishing a newer episode moves latestEpisodeDate onto the mirrored row")
    func refreshCarriesLatestEpisodeDate() throws {
        let schema = Schema([SubscribedPodcastModel.self, PodcastInfoModel.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let info = PodcastInfo(
            title: "Cadence", description: nil,
            episodes: [PodcastEpisodeInfo(title: "Ep 1", pubDate: old, audioURL: "https://x/1.mp3")],
            rssUrl: "https://example.com/cadence.xml", imageURL: "", language: "en"
        )
        let podcast = PodcastInfoModel(podcastInfo: info, lastUpdated: Date(), isSubscribed: true)
        context.insert(podcast)
        try context.save()

        let coordinator = SubscriptionSyncCoordinator()
        coordinator.setModelContainer(container)

        func mirroredDate() -> Date? {
            (try? context.fetch(FetchDescriptor<SubscribedPodcastModel>()))?.first?.latestEpisodeDate
        }
        #expect(mirroredDate() == old)

        // The feed publishes. applyPodcastInfo is the funnel every refresh path
        // goes through, and it recomputes latestEpisodeDate.
        let fresh = Date(timeIntervalSince1970: 1_800_000_000)
        podcast.applyPodcastInfo(
            PodcastInfo(
                title: "Cadence", description: nil,
                episodes: [
                    PodcastEpisodeInfo(title: "Ep 1", pubDate: old, audioURL: "https://x/1.mp3"),
                    PodcastEpisodeInfo(title: "Ep 2", pubDate: fresh, audioURL: "https://x/2.mp3"),
                ],
                rssUrl: "https://example.com/cadence.xml", imageURL: "", language: "en"
            )
        )
        try context.save()

        // Without the refresh the row still carries the old date — the mirror is
        // only written on subscribe/unsubscribe otherwise.
        coordinator.refreshMirroredMetadata()
        #expect(mirroredDate() == fresh)
    }
}
