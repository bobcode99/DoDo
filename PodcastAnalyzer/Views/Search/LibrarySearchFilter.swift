//
//  LibrarySearchFilter.swift
//  PodcastAnalyzer
//
//  Library-tab matching, kept free of views and SwiftData so it can be tested
//  with plain PodcastInfo values.
//

import Foundation

/// An episode from a subscribed show that matched the library search.
struct LibrarySearchEpisode {
    let episode: PodcastEpisodeInfo
    let podcastTitle: String
    let podcastImageURL: String
    let podcastLanguage: String
}

enum LibrarySearchFilter {
    /// Episodes whose title or description contains `query`, in show order.
    /// Takes the decoded infos, not the models: reading `podcastInfo`
    /// re-materializes the whole episode array, so the caller binds it once
    /// per show instead of per match — this runs on every keystroke.
    static func episodes(in shows: [PodcastInfo], matching query: String) -> [LibrarySearchEpisode] {
        guard !query.isEmpty else { return [] }
        return shows.flatMap { info in
            info.episodes
                .filter { episode in
                    episode.title.localizedStandardContains(query) ||
                    (episode.podcastEpisodeDescription?.localizedStandardContains(query) ?? false)
                }
                .map { episode in
                    LibrarySearchEpisode(
                        episode: episode,
                        podcastTitle: info.title,
                        podcastImageURL: info.imageURL,
                        podcastLanguage: info.language
                    )
                }
        }
    }
}
