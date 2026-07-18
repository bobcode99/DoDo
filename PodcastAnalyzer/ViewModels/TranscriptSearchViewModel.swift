//
//  TranscriptSearchViewModel.swift
//  PodcastAnalyzer
//
//  ViewModel for cross-podcast transcript search (Phase 1).
//  Heavy file I/O and string matching run off MainActor via @concurrent static methods.
//

import Observation
import Foundation

// MARK: - Result Types

struct TranscriptSearchResult: Identifiable, Sendable {
    /// Unique ID composed of podcast title + episode ID, separated by U+001F (unit separator).
    let id: String
    let episode: PodcastEpisodeInfo
    let podcastTitle: String
    let podcastImageURL: String
    let podcastLanguage: String
    let matchCount: Int
    /// Up to 3 representative matches shown as snippets in the results list.
    let snippets: [TranscriptMatch]
}

struct TranscriptMatch: Identifiable, Sendable {
    /// Segment index from the SRT file (TranscriptSegment.id).
    let id: Int
    let timestamp: TimeInterval
    let text: String
}

// MARK: - ViewModel

@MainActor @Observable
final class TranscriptSearchViewModel {

    // MARK: Observable state

    /// All results from the last search, unfiltered.
    private var allResults: [TranscriptSearchResult] = []
    /// Results filtered by `selectedPodcastFilter` for display.
    var results: [TranscriptSearchResult] {
        guard let filter = selectedPodcastFilter else { return allResults }
        return allResults.filter { $0.podcastTitle == filter }
    }
    var isSearching = false
    /// When non-nil, filters results to the named podcast.
    var selectedPodcastFilter: String? = nil

    // MARK: Search

    /// Launches a parallel transcript search across all subscribed podcasts.
    /// Must be called from MainActor; extracts Sendable `PodcastInfo` values first
    /// so that the nonisolated worker never touches non-Sendable SwiftData models.
    func performSearch(query: String, podcasts: [PodcastInfoModel]) async {
        guard !query.isEmpty else {
            allResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        // Extract Sendable value types here, on MainActor, before hopping off.
        let podcastInfos: [PodcastInfo] = podcasts.map(\.podcastInfo)

        let found = await Self.searchTranscripts(
            query: query,
            podcasts: podcastInfos
        )

        guard !Task.isCancelled else { return }
        allResults = found
    }

    // MARK: - Off-actor search

    /// Searches transcript SRT files across all podcasts in parallel.
    /// Annotated @concurrent so Swift 6.2 actually runs this on the cooperative
    /// thread pool rather than inheriting the caller's MainActor executor.
    @concurrent private nonisolated static func searchTranscripts(
        query: String,
        podcasts: [PodcastInfo]
    ) async -> [TranscriptSearchResult] {
        await withTaskGroup(of: [TranscriptSearchResult].self) { group in
            for podcast in podcasts {
                group.addTask {
                    do {
                        return try await searchPodcast(query: query, podcast: podcast)
                    } catch {
                        return []
                    }
                }
            }

            var all: [TranscriptSearchResult] = []
            for await batch in group {
                all.append(contentsOf: batch)
            }
            // Sort by most matches descending.
            return all.sorted { $0.matchCount > $1.matchCount }
        }
    }

    /// Searches a single podcast's episodes for transcript matches.
    /// Checks cancellation between episodes for fast response on rapid typing.
    @concurrent private nonisolated static func searchPodcast(
        query: String,
        podcast: PodcastInfo
    ) async throws -> [TranscriptSearchResult] {
        var results: [TranscriptSearchResult] = []

        for episode in podcast.episodes {
            try Task.checkCancellation()

            let episodeTitle = episode.title
            let podcastTitle = podcast.title

            guard let segments = await MainActor.run(body: {
                TranscriptStore.shared.loadSegments(episodeTitle: episodeTitle, podcastTitle: podcastTitle)
            }) else {
                continue
            }

            let matchingSegments = segments.filter {
                $0.text.localizedCaseInsensitiveContains(query)
            }

            guard !matchingSegments.isEmpty else { continue }

            let snippets = matchingSegments.prefix(3).map { seg in
                TranscriptMatch(
                    id: seg.id,
                    timestamp: seg.startTime,
                    text: seg.text
                )
            }

            // Replicate PodcastEpisodeInfo.id logic without crossing actor boundary.
            let episodeID: String = {
                if let url = episode.audioURL { return url }
                let dateString = episode.pubDate?.timeIntervalSince1970.description ?? "unknown"
                return "\(episodeTitle)_\(dateString)"
            }()

            let result = TranscriptSearchResult(
                id: "\(podcastTitle)\u{1F}\(episodeID)",
                episode: episode,
                podcastTitle: podcastTitle,
                podcastImageURL: podcast.imageURL,
                podcastLanguage: podcast.language,
                matchCount: matchingSegments.count,
                snippets: Array(snippets)
            )
            results.append(result)
        }

        return results
    }
}
