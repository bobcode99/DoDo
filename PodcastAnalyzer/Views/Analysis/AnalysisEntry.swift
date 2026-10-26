//
//  AnalysisEntry.swift
//  PodcastAnalyzer
//
//  Row data for AnalysisView: transcripts and AI analyses merged into one
//  entry per episode, plus the navigation routes each row needs.
//

import Foundation

struct AnalysisEntry {
  let podcastTitle: String
  let episodeTitle: String
  var transcriptDate: Date?
  var analysis: EpisodeAIAnalysis?

  var updatedAt: Date {
    max(analysis?.updatedAt ?? .distantPast, transcriptDate ?? .distantPast)
  }

  /// Transcripts and analyses merged by episode key.
  ///
  /// Analysis rows must carry content — same rule the episode-row sparkles
  /// badge uses (EpisodeStatusChecker.hasAIAnalysis). Q&A-only rows are legit
  /// (the card shows a Q&A badge). Rows with neither come from a Q&A save
  /// whose encode failed or a partially-synced CloudKit record, and would
  /// list an episode that visibly "has no analysis".
  ///
  /// `analyses` must be sorted newest-first so the first content row per key wins.
  static func merge(
    transcripts: [EpisodeTranscriptModel], analyses: [EpisodeAIAnalysis]
  ) -> [AnalysisEntry] {
    var byKey: [String: AnalysisEntry] = [:]
    for transcript in transcripts {
      guard let parsed = EpisodeKeyUtils.parseKey(transcript.episodeId) else { continue }
      byKey[transcript.episodeId] = AnalysisEntry(
        podcastTitle: parsed.podcastTitle, episodeTitle: parsed.episodeTitle,
        transcriptDate: transcript.generatedAt)
    }
    for analysis in analyses where analysis.hasAnalysis || !(analysis.qaHistoryJSON ?? "").isEmpty {
      let key = EpisodeKeyUtils.makeKey(
        podcastTitle: analysis.podcastTitle, episodeTitle: analysis.episodeTitle)
      guard byKey[key]?.analysis == nil else { continue }
      byKey[key, default: AnalysisEntry(
        podcastTitle: analysis.podcastTitle, episodeTitle: analysis.episodeTitle
      )].analysis = analysis
    }
    return Array(byKey.values)
  }
}

// MARK: - Row

struct AnalysisRow: Identifiable {
  let entry: AnalysisEntry
  let artworkURL: String?
  let aiRoute: EpisodeAIAnalysisRoute
  let transcriptRoute: EpisodeTranscriptRoute
  let detailRoute: EpisodeDetailRoute

  var id: String {
    EpisodeKeyUtils.makeKey(podcastTitle: entry.podcastTitle, episodeTitle: entry.episodeTitle)
  }

  /// Builds every route for the given entries in one pass. `podcastInfo`
  /// decodes the podcast's whole episode blob on each access, so it's read
  /// once per show here rather than once per route per row.
  static func make(
    for entries: [AnalysisEntry], podcastByTitle: [String: PodcastInfoModel]
  ) -> [AnalysisRow] {
    var infoCache: [String: PodcastInfo?] = [:]
    return entries.map { entry in
      let podcast = podcastByTitle[entry.podcastTitle]
      let info = infoCache[entry.podcastTitle] ?? podcast?.podcastInfo
      infoCache[entry.podcastTitle] = info
      let episode = enrichedEpisode(for: entry, info: info)
      let fallback = podcast?.imageURL
      return AnalysisRow(
        entry: entry,
        artworkURL: episode.imageURL ?? fallback,
        aiRoute: EpisodeAIAnalysisRoute(
          episode: episode, podcastTitle: entry.podcastTitle, fallbackImageURL: fallback,
          podcastLanguage: info?.language, zoomsFromSource: true),
        transcriptRoute: EpisodeTranscriptRoute(
          episode: episode, podcastTitle: entry.podcastTitle, fallbackImageURL: fallback,
          podcastLanguage: info?.language),
        detailRoute: EpisodeDetailRoute(
          episode: episode, podcastTitle: entry.podcastTitle, fallbackImageURL: fallback,
          podcastLanguage: info?.language)
      )
    }
  }

  /// Returns the full `PodcastEpisodeInfo` from the podcast's cached feed
  /// (with description, pubDate, duration, etc.) when available. Falls back
  /// to a minimal stub if the podcast was never cached or the episode is gone
  /// from the feed — without this, EpisodeDetailView's summary is blank.
  private static func enrichedEpisode(
    for entry: AnalysisEntry, info: PodcastInfo?
  ) -> PodcastEpisodeInfo {
    let audioURL = entry.analysis?.episodeAudioURL ?? ""
    let storedAudioURL = audioURL.isEmpty ? nil : audioURL
    if let episodes = info?.episodes,
       let match = episodes.first(where: { episode in
         if let storedAudioURL, let url = episode.audioURL, url == storedAudioURL {
           return true
         }
         return episode.title == entry.episodeTitle
       }) {
      return match
    }
    return PodcastEpisodeInfo(
      title: entry.episodeTitle,
      audioURL: storedAudioURL
    )
  }
}
