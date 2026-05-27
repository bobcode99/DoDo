//
//  AnalysisView.swift
//  PodcastAnalyzer
//
//  Top-level tab/destination listing every episode that has a stored
//  EpisodeAIAnalysis. Tap a row to push the existing per-episode AI page
//  where the user can review the analysis and keep asking questions.
//

import SwiftData
import SwiftUI

struct AnalysisView: View {
  @Query(sort: \EpisodeAIAnalysis.updatedAt, order: .reverse)
  private var analyses: [EpisodeAIAnalysis]

  @Query(filter: #Predicate<PodcastInfoModel> { $0.isSubscribed })
  private var podcasts: [PodcastInfoModel]

  @State private var searchText: String = ""

  private var podcastByTitle: [String: PodcastInfoModel] {
    Dictionary(podcasts.map { ($0.title, $0) }, uniquingKeysWith: { first, _ in first })
  }

  private var filteredAnalyses: [EpisodeAIAnalysis] {
    let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return analyses }
    let needle = trimmed.lowercased()
    return analyses.filter {
      $0.episodeTitle.lowercased().contains(needle)
        || $0.podcastTitle.lowercased().contains(needle)
    }
  }

  var body: some View {
    Group {
      if analyses.isEmpty {
        ContentUnavailableView {
          Label("No Analyses Yet", systemImage: Constants.analysisIconName)
        } description: {
          Text("Run AI analysis on an episode and it will show up here for quick browsing and follow-up questions.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if filteredAnalyses.isEmpty {
        ContentUnavailableView.search(text: searchText)
      } else {
        ScrollView {
          LazyVStack(spacing: 12) {
            ForEach(filteredAnalyses) { analysis in
              NavigationLink(value: route(for: analysis)) {
                AnalysisRowCard(
                  analysis: analysis,
                  artworkURL: podcastByTitle[analysis.podcastTitle]?.podcastInfo.imageURL
                )
              }
              .buttonStyle(.plain)
              .contextMenu {
                NavigationLink(value: episodeDetailRoute(for: analysis)) {
                  Label("View Episode", systemImage: "doc.text")
                }
                if let podcast = podcastByTitle[analysis.podcastTitle] {
                  NavigationLink(value: PodcastBrowseRoute(podcastModel: podcast)) {
                    Label("View Show", systemImage: "list.bullet")
                  }
                }
              }
            }
          }
          .padding(16)
        }
      }
    }
    .navigationTitle(Constants.analysisString)
    #if os(iOS)
    .navigationBarTitleDisplayMode(.large)
    #endif
    .searchable(text: $searchText, prompt: "Search analyses")
  }

  private func route(for analysis: EpisodeAIAnalysis) -> EpisodeAIAnalysisRoute {
    let podcast = podcastByTitle[analysis.podcastTitle]
    return EpisodeAIAnalysisRoute(
      episode: enrichedEpisode(for: analysis, podcast: podcast),
      podcastTitle: analysis.podcastTitle,
      fallbackImageURL: podcast?.podcastInfo.imageURL,
      podcastLanguage: podcast?.podcastInfo.language
    )
  }

  private func episodeDetailRoute(for analysis: EpisodeAIAnalysis) -> EpisodeDetailRoute {
    let podcast = podcastByTitle[analysis.podcastTitle]
    return EpisodeDetailRoute(
      episode: enrichedEpisode(for: analysis, podcast: podcast),
      podcastTitle: analysis.podcastTitle,
      fallbackImageURL: podcast?.podcastInfo.imageURL,
      podcastLanguage: podcast?.podcastInfo.language
    )
  }

  /// Returns the full `PodcastEpisodeInfo` from the subscribed podcast's feed
  /// (with description, pubDate, duration, etc.) when available. Falls back
  /// to a minimal stub if the podcast isn't subscribed or the episode is gone
  /// from the feed — without this, EpisodeDetailView's summary is blank.
  private func enrichedEpisode(
    for analysis: EpisodeAIAnalysis,
    podcast: PodcastInfoModel?
  ) -> PodcastEpisodeInfo {
    let storedAudioURL = analysis.episodeAudioURL.isEmpty ? nil : analysis.episodeAudioURL
    if let episodes = podcast?.podcastInfo.episodes,
       let match = episodes.first(where: { episode in
         if let storedAudioURL, let url = episode.audioURL, url == storedAudioURL {
           return true
         }
         return episode.title == analysis.episodeTitle
       }) {
      return match
    }
    return PodcastEpisodeInfo(
      title: analysis.episodeTitle,
      audioURL: storedAudioURL
    )
  }
}

// MARK: - Row Card

private struct AnalysisRowCard: View {
  let analysis: EpisodeAIAnalysis
  let artworkURL: String?

  private var overviewSnippet: String? {
    analysis.parsedAnalysis?.overview
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nonEmptyOrNil
  }

  private var qaCount: Int {
    analysis.qaHistory.count
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      artwork
      VStack(alignment: .leading, spacing: 6) {
        Text(analysis.podcastTitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Text(analysis.episodeTitle)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)
          .lineLimit(2)
        if let snippet = overviewSnippet {
          Text(snippet)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }
        HStack(spacing: 10) {
          Label(analysis.updatedAt.formatted(date: .abbreviated, time: .omitted),
                systemImage: "clock")
            .font(.caption2)
            .foregroundStyle(.secondary)
          if qaCount > 0 {
            Label("\(qaCount) Q&A", systemImage: "bubble.left.and.bubble.right")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(Color.platformSystemGray6, in: .rect(cornerRadius: 14))
  }

  @ViewBuilder
  private var artwork: some View {
    let urlString = artworkURL ?? ""
    let url = URL(string: urlString)
    CachedAsyncImage(url: url) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      ZStack {
        Color.platformSystemGray5
        Image(systemName: Constants.analysisIconName)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 64, height: 64)
    .clipShape(.rect(cornerRadius: 8))
  }
}

// MARK: - Small string helper

private extension String {
  var nonEmptyOrNil: String? { isEmpty ? nil : self }
}
