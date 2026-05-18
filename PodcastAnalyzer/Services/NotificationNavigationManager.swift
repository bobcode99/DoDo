//
//  NotificationNavigationManager.swift
//  PodcastAnalyzer
//
//  Handles notification tap navigation to EpisodeDetailView
//

import SwiftUI
import Foundation
import Observation
import SwiftData
import OSLog

// MARK: - Notification Navigation Target

struct NotificationNavigationTarget: Equatable {
  let podcastTitle: String
  let episodeTitle: String
  let audioURL: String
  let imageURL: String
  let language: String
}

// MARK: - Notification Navigation Manager
@Observable
@MainActor
class NotificationNavigationManager {
    static let shared = NotificationNavigationManager()
    
    var shouldNavigate = false
    var navigationTarget: NotificationNavigationTarget?
    var shouldExpandPlayer = false

    @ObservationIgnored
    private var modelContext: ModelContext?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContext = container.mainContext
    }

    func clearNavigation() {
        shouldNavigate = false
        navigationTarget = nil
    }
    
    // Improved lookup logic
    func findEpisode(podcastTitle: String, episodeTitle: String) -> (episode: PodcastEpisodeInfo, imageURL: String?, language: String)? {
        guard let context = modelContext else { return nil }

        let descriptor = FetchDescriptor<PodcastInfoModel>(
            predicate: #Predicate { $0.title == podcastTitle }
        )

        guard let podcast = try? context.fetch(descriptor).first,
              let episode = podcast.podcastInfo.episodes.first(where: { $0.title == episodeTitle }) else {
            return nil
        }

        return (episode, podcast.podcastInfo.imageURL, "en")
    }

    /// Find episode by audio URL (for widget deep links)
    func findEpisodeByAudioURL(_ audioURL: String) -> (episode: PodcastEpisodeInfo, podcastTitle: String, imageURL: String?, language: String)? {
        guard let context = modelContext else { return nil }

        let descriptor = FetchDescriptor<PodcastInfoModel>()

        guard let podcasts = try? context.fetch(descriptor) else { return nil }

        for podcast in podcasts {
            if let episode = podcast.podcastInfo.episodes.first(where: { $0.audioURL == audioURL }) {
                return (episode, podcast.podcastInfo.title, podcast.podcastInfo.imageURL, podcast.podcastInfo.language)
            }
        }

        return nil
    }

    /// Navigate to episode from widget deep link
    func navigateToEpisode(audioURL: String) {
        guard let result = findEpisodeByAudioURL(audioURL) else { return }

        navigationTarget = NotificationNavigationTarget(
            podcastTitle: result.podcastTitle,
            episodeTitle: result.episode.title,
            audioURL: audioURL,
            imageURL: result.imageURL ?? "",
            language: result.language
        )
        shouldNavigate = true
    }

    /// Request expanding the player (from widget tap)
    func requestExpandPlayer() {
        shouldExpandPlayer = true
    }

    /// Navigate to episode detail from widget deep link
    func navigateToEpisodeDetail(title: String, podcastTitle: String, audioURL: String, imageURL: String) {
        // Try to find the full episode in SwiftData first
        if !audioURL.isEmpty, let result = findEpisodeByAudioURL(audioURL) {
            navigationTarget = NotificationNavigationTarget(
                podcastTitle: result.podcastTitle,
                episodeTitle: result.episode.title,
                audioURL: audioURL,
                imageURL: result.imageURL ?? imageURL,
                language: result.language
            )
        } else {
            navigationTarget = NotificationNavigationTarget(
                podcastTitle: podcastTitle,
                episodeTitle: title,
                audioURL: audioURL,
                imageURL: imageURL,
                language: "en"
            )
        }
        shouldNavigate = true
    }

    /// Navigate to currently playing episode
    func navigateToNowPlaying() {
        guard let currentEpisode = EnhancedAudioManager.shared.currentEpisode else { return }

        navigationTarget = NotificationNavigationTarget(
            podcastTitle: currentEpisode.podcastTitle,
            episodeTitle: currentEpisode.title,
            audioURL: currentEpisode.audioURL,
            imageURL: currentEpisode.imageURL ?? "",
            language: "en"
        )
        shouldNavigate = true
    }
}