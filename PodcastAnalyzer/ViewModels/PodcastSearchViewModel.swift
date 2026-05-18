//
//  PodcastSearchViewModel.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2025/12/23.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class PodcastSearchViewModel {
  var searchText = ""
  var podcasts: [Podcast] = []
  var isLoading = false

  var selectedPodcastId: Int? = nil
  var episodesForSelectedPodcast: [Episode]? = nil
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
      return
    }

    // Cancel previous search
    searchTask?.cancel()

    isLoading = true
    podcasts = []

    searchTask = Task {
      do {
        let results = try await service.searchPodcasts(term: searchText, limit: 20)
        if !Task.isCancelled {
          podcasts = results
        }
      } catch {
        if !Task.isCancelled {
          print("Search error: \(error)")
        }
      }
      if !Task.isCancelled {
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
          print("RSS error: \(error)")
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
