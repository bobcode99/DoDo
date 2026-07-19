//
//  LibraryEpisodeActions.swift
//  PodcastAnalyzer
//
//  Shared episode actions for Library sub-views (Saved, Downloaded, Latest).
//  Eliminates duplication of batchFetch, toggleStar, togglePlayed, download, delete.
//

import SwiftData

@MainActor
enum LibraryEpisodeActions {
  /// Fetch all EpisodeDownloadModels keyed by ID for batch lookups.
  static func batchFetchEpisodeModels(from context: ModelContext) -> [String: EpisodeDownloadModel] {
    let descriptor = FetchDescriptor<EpisodeDownloadModel>()
    guard let results = try? context.fetch(descriptor) else { return [:] }
    var models: [String: EpisodeDownloadModel] = [:]
    for model in results { models[model.id] = model }
    return models
  }

  /// Toggle the star/saved state of an episode.
  /// When `createIfMissing` is true, creates an EpisodeDownloadModel if none exists (used by LatestEpisodesView).
  static func toggleStar(
    _ episode: LibraryEpisode,
    episodeModels: inout [String: EpisodeDownloadModel],
    context: ModelContext,
    createIfMissing: Bool = false
  ) {
    if let model = episodeModels[episode.id] {
      model.isStarred.toggle()
      try? context.save()
    } else if createIfMissing, let audioURL = episode.episodeInfo.audioURL {
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: audioURL,
        imageURL: episode.imageURL ?? "",
        pubDate: episode.episodeInfo.pubDate
      )
      model.isStarred = true
      context.insert(model)
      try? context.save()
      episodeModels[episode.id] = model
    }
  }

  /// Toggle the played/completed state of an episode.
  /// When `createIfMissing` is true, creates an EpisodeDownloadModel if none exists (used by LatestEpisodesView).
  static func togglePlayed(
    _ episode: LibraryEpisode,
    episodeModels: inout [String: EpisodeDownloadModel],
    context: ModelContext,
    createIfMissing: Bool = false
  ) {
    if let model = episodeModels[episode.id] {
      model.setCompleted(!model.isCompleted)
      model.lastPlaybackPosition = 0
      try? context.save()
    } else if createIfMissing, let audioURL = episode.episodeInfo.audioURL {
      let model = EpisodeDownloadModel(
        episodeTitle: episode.episodeInfo.title,
        podcastTitle: episode.podcastTitle,
        audioURL: audioURL,
        imageURL: episode.imageURL ?? "",
        pubDate: episode.episodeInfo.pubDate
      )
      context.insert(model)
      model.setCompleted(true)
      try? context.save()
      episodeModels[episode.id] = model
    }
  }

  /// Start downloading an episode.
  static func downloadEpisode(_ episode: LibraryEpisode) {
    DownloadManager.shared.downloadEpisode(
      episode: episode.episodeInfo,
      podcastTitle: episode.podcastTitle,
      language: episode.language
    )
  }

  /// Delete a downloaded episode's local audio file and clear the model's local path.
  static func deleteDownload(
    _ episode: LibraryEpisode,
    episodeModels: [String: EpisodeDownloadModel],
    context: ModelContext
  ) {
    DownloadManager.shared.deleteDownload(
      episodeTitle: episode.episodeInfo.title,
      podcastTitle: episode.podcastTitle
    )
    if let model = episodeModels[episode.id] {
      model.localAudioPath = nil
      try? context.save()
    }
  }
}
