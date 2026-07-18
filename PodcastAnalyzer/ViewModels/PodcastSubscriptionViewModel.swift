//
//  PodcastSubscriptionViewModel.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/3/14.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PodcastSubscriptionViewModel {
  var isSubscribing = false
  var subscriptionError: String?
  var subscriptionSuccess = false

  @ObservationIgnored
  private var subscribeTask: Task<Void, Never>?

  @ObservationIgnored
  private let applePodcastService = ApplePodcastService()

  @ObservationIgnored
  private let rssService = PodcastRssService()

  func isAlreadySubscribed(_ podcast: AppleRSSPodcast, in context: ModelContext) -> Bool {
    let name = podcast.name
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.title == name }
    )
    return (try? context.fetch(descriptor).first) != nil
  }

  func subscribeToPodcast(_ podcast: AppleRSSPodcast, context: ModelContext) {
    isSubscribing = true
    subscriptionError = nil
    subscriptionSuccess = false

    subscribeTask?.cancel()
    subscribeTask = Task {
      do {
        // Look up the podcast to get the RSS feed URL
        guard let result = try await applePodcastService.lookupPodcast(collectionId: podcast.id),
              let feedUrl = result.feedUrl else {
          subscriptionError = "Could not find RSS feed"
          isSubscribing = false
          return
        }

        // Fetch podcast info from RSS
        let podcastInfo = try await rssService.fetchPodcast(from: feedUrl)

        if let existingByRSS = try? context.fetch(FetchDescriptor<PodcastInfoModel>(
          predicate: #Predicate { $0.rssUrl == feedUrl }
        )).first {
          existingByRSS.isSubscribed = true
          existingByRSS.applyPodcastInfo(podcastInfo)
          existingByRSS.lastUpdated = Date()
          try context.save()
          subscriptionSuccess = true
          isSubscribing = false
          return
        }

        let title = podcastInfo.title
        let existingDescriptor = FetchDescriptor<PodcastInfoModel>(
          predicate: #Predicate { $0.title == title }
        )

        if let existingByTitle = try? context.fetch(existingDescriptor).first {
          existingByTitle.isSubscribed = true
          existingByTitle.applyPodcastInfo(podcastInfo)
          existingByTitle.lastUpdated = Date()
          try context.save()
          subscriptionSuccess = true
          isSubscribing = false
          return
        }

        // Create new subscription
        let model = PodcastInfoModel(podcastInfo: podcastInfo, lastUpdated: Date(), isSubscribed: true)
        context.insert(model)
        try context.save()
        SubscriptionSyncCoordinator.shared.sync(from: model)

        subscriptionSuccess = true
      } catch {
        subscriptionError = error.localizedDescription
      }

      isSubscribing = false
    }
  }

  func cleanup() {
    subscribeTask?.cancel()
    subscribeTask = nil
  }
}
