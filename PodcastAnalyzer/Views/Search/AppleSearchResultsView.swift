//
//  AppleSearchResultsView.swift
//  PodcastAnalyzer
//
//  Podcasts-tab results: matching shows, then matching episodes from any show,
//  subscribed or not.
//

import SwiftUI

struct AppleSearchResultsView: View {
    let isLoading: Bool
    let podcasts: [Podcast]
    let episodes: [ApplePodcastService.TrendingEpisode]
    let isSubscribed: (Podcast) -> Bool
    let onSubscribe: (Podcast) -> Void
    /// Pushes through the parent, which owns the keyboard-dismiss dance; see
    /// `PodcastSearchView.navigate(_:)`. That is also why rows are Buttons,
    /// not NavigationLinks.
    let onNavigate: (any Hashable) -> Void

    var body: some View {
        if isLoading {
            VStack {
                Spacer()
                ProgressView("Searching...")
                Spacer()
            }
        } else if podcasts.isEmpty && episodes.isEmpty {
            // The data source is named here and nowhere else: before a
            // search it is trivia, but the moment a show is missing it is
            // the explanation *and* the way out. A directory nobody
            // mentioned looks like a broken search.
            VStack(spacing: 8) {
                Spacer()
                Text("No results found")
                    .foregroundStyle(.secondary)
                Text("Search covers the Apple Podcasts directory. If a show isn't listed there, add it by RSS URL in Settings ▸ Subscriptions.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
        } else {
            List {
                if !podcasts.isEmpty {
                    Section("Shows") {
                        ForEach(podcasts, id: \.collectionId) { podcast in
                            Button {
                                onNavigate(PodcastBrowseRoute(
                                    podcastName: podcast.collectionName,
                                    artworkURL: podcast.artworkUrl100 ?? "",
                                    artistName: podcast.artistName,
                                    collectionId: String(podcast.collectionId),
                                    applePodcastURL: nil
                                ))
                            } label: {
                                HStack {
                                    ApplePodcastRow(
                                        podcast: podcast,
                                        isSubscribed: isSubscribed(podcast),
                                        onSubscribe: { onSubscribe(podcast) }
                                    )
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !episodes.isEmpty {
                    Section("Episodes") {
                        ForEach(episodes, id: \.episode.id) { episode in
                            Button {
                                onNavigate(TrendingEpisodeDetailDestination(from: episode))
                            } label: {
                                TrendingEpisodeRow(episode: episode, rank: nil)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                TrendingEpisodeContextMenu(episode: episode)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
