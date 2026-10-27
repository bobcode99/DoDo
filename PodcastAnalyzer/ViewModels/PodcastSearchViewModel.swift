//
//  PodcastSearchViewModel.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/23.
//

import SwiftUI
import Observation
import OSLog

private let logger = Logger(subsystem: "com.podcast.analyzer", category: "PodcastSearchViewModel")

@MainActor
@Observable
final class PodcastSearchViewModel {
  var searchText = ""
  var podcasts: [Podcast] = []
  /// Episode matches from any show, subscribed or not, listed under the shows.
  var episodes: [ApplePodcastService.TrendingEpisode] = []
  var isLoading = false

  var selectedPodcastId: Int?
  var episodesForSelectedPodcast: [Episode]?
  var isLoadingEpisodes = false

  @ObservationIgnored
  private let service = ApplePodcastService()

  @ObservationIgnored
  private var searchTask: Task<Void, Never>?

  @ObservationIgnored
  private var episodeTask: Task<Void, Never>?

  func performSearch() {
    guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
      podcasts = []
      episodes = []
      return
    }

    // Cancel previous search
    searchTask?.cancel()

    isLoading = true
    podcasts = []
    episodes = []

    searchTask = Task {
      let term = searchText
      // Runs alongside the show search; a failure here only costs the
      // episode section, never the shows.
      async let foundEpisodes = try? service.searchEpisodes(term: term)
      do {
        let results = try await service.searchPodcasts(term: term, limit: 20)
        if !Task.isCancelled {
          podcasts = results
        }
      } catch {
        if !Task.isCancelled {
          logger.error("Search error: \(error.localizedDescription, privacy: .public)")
        }
      }
      let episodeResults = await foundEpisodes ?? []
      if !Task.isCancelled {
        episodes = episodeResults.map(ApplePodcastService.TrendingEpisode.init(searchResult:))
        isLoading = false
      }
    }
  }

  func loadEpisodes(from feedUrl: String) {
    // Cancel previous episode load
    episodeTask?.cancel()

    isLoadingEpisodes = true
    episodesForSelectedPodcast = nil

    episodeTask = Task {
      do {
        let episodes = try await service.fetchEpisodesFromRSS(feedUrl: feedUrl, limit: 20)
        if !Task.isCancelled {
          episodesForSelectedPodcast = episodes
        }
      } catch {
        if !Task.isCancelled {
          logger.error("RSS error: \(error.localizedDescription, privacy: .public)")
        }
      }
      if !Task.isCancelled {
        isLoadingEpisodes = false
      }
    }
  }

  func cleanup() {
    searchTask?.cancel()
    searchTask = nil
    episodeTask?.cancel()
    episodeTask = nil
  }
}
