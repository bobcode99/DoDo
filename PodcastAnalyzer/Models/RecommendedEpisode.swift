//
//  RecommendedEpisode.swift
//  PodcastAnalyzer
//
//  An episode the on-device model picked, with the reason it gave.
//
//  The reason used to be generated and thrown away: the model produced one per
//  pick on every run and `HomeViewModel` read only the numbers. Carrying it costs
//  nothing — the tokens were already spent — and it is the difference between a
//  row of episodes and a row that explains itself.
//

import Foundation

struct RecommendedEpisode: Identifiable, Equatable {
  /// nil when the model returned fewer reasons than picks.
  let reason: String?
  let episode: LibraryEpisode

  var id: String { episode.id }
}

/// Why For You has nothing to show.
enum RecommendationFailure: Equatable {
  case modelUnavailable
  case noHistory
  case noCandidates
  case generationFailed
}
