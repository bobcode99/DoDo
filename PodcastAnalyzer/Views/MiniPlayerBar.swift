//
//  MiniPlayerBar.swift
//  PodcastAnalyzer
//
//  Compact mini player bar that shows at bottom of TabView
//

import SwiftData
import SwiftUI

/// Navigation state for expanded player -> main nav transitions
enum ExpandedPlayerNavigation: Equatable {
  case none
  case episodeDetail(PodcastEpisodeInfo, podcastTitle: String, imageURL: String?, language: String?)
  case podcastEpisodeList(PodcastInfoModel)

  static func == (lhs: ExpandedPlayerNavigation, rhs: ExpandedPlayerNavigation) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
      return true
    case let (.episodeDetail(e1, t1, i1, _), .episodeDetail(e2, t2, i2, _)):
      return e1.title == e2.title && t1 == t2 && i1 == i2
    case let (.podcastEpisodeList(p1), .podcastEpisodeList(p2)):
      return p1.id == p2.id
    default:
      return false
    }
  }
}

struct MiniPlayerBar: View {
  @Environment(\.tabViewBottomAccessoryPlacement) var placement
  @Environment(\.modelContext) private var modelContext
  @Environment(\.tabNavigationCoordinator) private var coordinator
  // Access singleton directly without @State to avoid unnecessary observation overhead
  private var audioManager: EnhancedAudioManager { .shared }
  @State private var showExpandedPlayer = false
  @State private var deferredNavigation: ExpandedPlayerNavigation = .none

  var body: some View {
    VStack(spacing: 0) {
      // Progress bar (hidden or 0 if not playing). Isolated into its own view
      // so the high-frequency currentTime ticks (~4×/sec during playback)
      // invalidate only the 3pt bar — not the whole accessory (artwork,
      // marquee, glass), which is drawn over every tab and otherwise
      // re-rendered on every tick, competing with navigation animations.
      MiniPlayerProgressBar()

      // Main content
      ZStack {
        Button(action: openExpandedPlayer) {
          Color.clear
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open expanded player")

        HStack(spacing: 12) {
          HStack(spacing: 12) {
            // Artwork or Placeholder
            Group {
              if let urlString = audioManager.currentEpisode?.imageURL, let url = URL(string: urlString) {

                CachedAsyncImage(url: url) { image in
                  image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                  Color.gray
                }
              } else {
                RoundedRectangle(cornerRadius: 8)
                  .fill(Color.gray.opacity(0.3))
                  .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
              }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Episode info
            VStack(alignment: .leading, spacing: 2) {
              // Branch rather than `?? String(localized:)`: a literal reaching
              // Text/LocalizedStringKey resolves through the environment locale,
              // and so follows the in-app language. A String fallback resolves
              // against the *system* language and stayed Chinese on a Chinese
              // device even with the app set to English.
              if let title = audioManager.currentEpisode?.title {
                MarqueeText(text: title, font: .subheadline, fontWeight: .medium)
              } else {
                Text("Not Playing")
                  .font(.subheadline)
                  .fontWeight(.medium)
                  .lineLimit(1)
              }

              if let podcastTitle = audioManager.currentEpisode?.podcastTitle {
                Text(podcastTitle)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              } else {
                Text("Select an episode to play")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
            }
          }
          .allowsHitTesting(false)

          Spacer()

          // Play/Pause button
          Button(action: {
            handlePlayPauseAction()
          }) {
            Image(systemName: audioManager.isPlaying ? "pause.fill" : "play.fill")
              .font(.title2)
              .frame(width: 32)
              .foregroundStyle(.primary)
          }
          .accessibilityLabel(audioManager.isPlaying ? "Pause" : "Play")
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .glassEffect(Glass.regular)
    }
    .sheet(isPresented: $showExpandedPlayer, onDismiss: handleExpandedPlayerDismissed) {
      ExpandedPlayerView(
        onNavigateToEpisodeDetail: { episode, podcastTitle, imageURL, language in
          deferredNavigation = .episodeDetail(episode, podcastTitle: podcastTitle, imageURL: imageURL, language: language)
        },
        onNavigateToPodcast: { podcast in
          deferredNavigation = .podcastEpisodeList(podcast)
        }
      )
      .presentationSizing(.page)
    }
    .onChange(of: NotificationNavigationManager.shared.shouldExpandPlayer) { _, shouldExpand in
      if shouldExpand {
        NotificationNavigationManager.shared.shouldExpandPlayer = false
        if audioManager.currentEpisode != nil {
          showExpandedPlayer = true
        }
      }
    }
  }

  // MARK: - Play/Pause Action

  private func openExpandedPlayer() {
    guard audioManager.currentEpisode != nil else { return }
    showExpandedPlayer = true
  }

  private func handlePlayPauseAction() {
    // Case 1: Currently playing - just pause
    if audioManager.isPlaying {
      audioManager.pause()
      return
    }

    // Case 2: Has current episode - resume
    if audioManager.currentEpisode != nil {
      audioManager.resume()
      return
    }

    // Case 3: No current episode - try to restore last played
    audioManager.restoreLastEpisode()
    if audioManager.currentEpisode != nil {
      // Successfully restored - start playing
      Task {
        try? await Task.sleep(for: .seconds(0.1))
        audioManager.resume()
      }
      return
    }

    // Case 4: No last episode - find one from SwiftData (async to avoid blocking UI)
    Task { @MainActor in
      if let episode = findEpisodeToPlay() {
        audioManager.play(
          episode: episode,
          audioURL: episode.audioURL,
          startTime: 0,
          imageURL: episode.imageURL,
          useDefaultSpeed: true
        )
      }
    }
  }

  private func handleExpandedPlayerDismissed() {
    guard deferredNavigation != .none else { return }
    let navigation = deferredNavigation
    deferredNavigation = .none

    switch navigation {
    case .none:
      break
    case let .episodeDetail(episode, podcastTitle, imageURL, language):
      coordinator?.activeRouter.push(
        EpisodeDetailRoute(
          episode: episode,
          podcastTitle: podcastTitle,
          fallbackImageURL: imageURL,
          podcastLanguage: language
        )
      )
    case let .podcastEpisodeList(podcastModel):
      coordinator?.activeRouter.push(
        PodcastBrowseRoute(podcastModel: podcastModel)
      )
    }
  }

  /// Finds an episode to play when there's no previous playback history
  /// Priority: 1. Most recently played (if any), 2. Random episode from subscribed podcasts
  private func findEpisodeToPlay() -> PlaybackEpisode? {
    // First try to find the most recently played episode from SwiftData
    let recentDescriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.lastPlayedDate != nil },
      sortBy: [SortDescriptor(\.lastPlayedDate, order: .reverse)]
    )

    if let recentModel = try? modelContext.fetch(recentDescriptor).first {
      return PlaybackEpisode(
        id: recentModel.id,
        title: recentModel.episodeTitle,
        podcastTitle: recentModel.podcastTitle,
        audioURL: recentModel.audioURL,
        imageURL: recentModel.imageURL,
        pubDate: recentModel.pubDate
      )
    }

    // No recently played - get a random episode from subscribed podcasts
    let podcastDescriptor = FetchDescriptor<PodcastInfoModel>()
    guard let podcasts = try? modelContext.fetch(podcastDescriptor),
          !podcasts.isEmpty else {
      return nil
    }

    // Collect all playable episodes (those with audio URLs) from all podcasts
    var playableEpisodes: [(episode: PodcastEpisodeInfo, audioURL: String, podcastTitle: String, podcastImageURL: String)] = []
    for podcast in podcasts {
      // One decode per podcast, not three.
      let info = podcast.podcastInfo
      let podcastTitle = info.title
      let podcastImageURL = info.imageURL
      for episode in info.episodes {
        // Only include episodes with valid audio URLs
        if let audioURL = episode.audioURL, !audioURL.isEmpty {
          playableEpisodes.append((episode, audioURL, podcastTitle, podcastImageURL))
        }
      }
    }

    guard !playableEpisodes.isEmpty else { return nil }

    // Pick a random episode
    let randomIndex = Int.random(in: 0..<playableEpisodes.count)
    let selected = playableEpisodes[randomIndex]

    return PlaybackEpisode(
      id: "\(selected.podcastTitle)\u{1F}\(selected.episode.title)",
      title: selected.episode.title,
      podcastTitle: selected.podcastTitle,
      audioURL: selected.audioURL,
      imageURL: selected.episode.imageURL ?? selected.podcastImageURL,
      episodeDescription: selected.episode.podcastEpisodeDescription,
      pubDate: selected.episode.pubDate,
      duration: selected.episode.duration,
      guid: selected.episode.guid
    )
  }
}

// MARK: - Isolated progress bar

/// Reads `currentTime`/`duration` only inside this 3pt bar, so the periodic
/// time-observer ticks (~4×/sec during playback) re-render just this view
/// instead of the whole MiniPlayerBar accessory.
private struct MiniPlayerProgressBar: View {
  private var audioManager: EnhancedAudioManager { .shared }

  private var progress: Double {
    guard audioManager.duration > 0 else { return 0 }
    return min(max(audioManager.currentTime / audioManager.duration, 0), 1)
  }

  var body: some View {
    ProgressView(value: progress)
      .progressViewStyle(.linear)
      .tint(.blue)
      .frame(height: 3)
      .opacity(audioManager.currentEpisode == nil ? 0 : 1)
  }
}

// MARK: - Preview

#Preview {
  MiniPlayerBar()
}
