//
//  LibrarySearchResultsView.swift
//  PodcastAnalyzer
//
//  Library-tab results: subscribed shows, then their matching episodes.
//

import SwiftUI

struct LibrarySearchResultsView: View {
    let podcasts: [PodcastInfoModel]
    let episodes: [LibrarySearchEpisode]
    let onNavigate: (any Hashable) -> Void
    let onPlay: (LibrarySearchEpisode) -> Void

    var body: some View {
        if podcasts.isEmpty && episodes.isEmpty {
            ContentUnavailableView.search
        } else {
            List {
                // Podcasts section
                if !podcasts.isEmpty {
                    Section {
                        ForEach(podcasts) { podcastModel in
                            LibraryPodcastRow(podcastModel: podcastModel) {
                                onNavigate(PodcastBrowseRoute(podcastModel: podcastModel))
                            }
                        }
                    }
                }

                // Episodes section
                if !episodes.isEmpty {
                    Section {
                        ForEach(episodes, id: \.episode.id) { item in
                            LibraryEpisodeRow(
                                episode: item.episode,
                                podcastTitle: item.podcastTitle,
                                podcastImageURL: item.podcastImageURL,
                                podcastLanguage: item.podcastLanguage,
                                onPlay: { onPlay(item) },
                                onOpen: {
                                    onNavigate(EpisodeDetailRoute(
                                        episode: item.episode,
                                        podcastTitle: item.podcastTitle,
                                        fallbackImageURL: item.podcastImageURL,
                                        podcastLanguage: item.podcastLanguage
                                    ))
                                }
                            )
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
