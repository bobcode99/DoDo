//
//  TrendingEpisodeContextMenu.swift
//  PodcastAnalyzer
//
//  Long-press / hard-press context menu for the "Top Episodes" cards on
//  HomeView. Reaches parity with EpisodeDetailView's ellipsis menu — star,
//  played, play-next, download/cancel/delete, share — even for episodes
//  the user hasn't subscribed to (the matching EpisodeDownloadModel is
//  created on demand, mirroring HomeViewModel.toggleStar's behavior).
//

import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TrendingEpisodeContextMenu: View {
  let episode: ApplePodcastService.TrendingEpisode

  @Environment(\.modelContext) private var modelContext

  // MARK: - Computed state

  private var episodeTitle: String { episode.episode.trackName }
  private var podcastTitle: String { episode.podcastName }
  private var audioURL: String? { episode.episode.episodeUrl }
  private var imageURL: String? {
    episode.episode.artworkUrl600
      ?? episode.episode.artworkUrl160
      ?? episode.podcastArtworkUrl
  }
  private var releaseDate: Date? {
    guard let raw = episode.episode.releaseDate else { return nil }
    return ISO8601DateFormatter().date(from: raw)
  }

  private var episodeKey: String {
    EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episodeTitle)
  }

  private var statusChecker: EpisodeStatusChecker {
    EpisodeStatusChecker(
      episodeTitle: episodeTitle,
      podcastTitle: podcastTitle,
      audioURL: audioURL
    )
  }

  private var downloadModel: EpisodeDownloadModel? {
    let key = episodeKey
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )
    return try? modelContext.fetch(descriptor).first
  }

  // MARK: - Body

  var body: some View {
    let model = downloadModel
    let isStarred = model?.isStarred ?? false
    let isCompleted = model?.isCompleted ?? false
    let state = statusChecker.downloadState

    goToShowSection
    Divider()
    starButton(isStarred: isStarred)
    playedButton(isCompleted: isCompleted)
    Divider()
    if audioURL != nil {
      playNextButton
      Divider()
    }
    downloadActions(state: state)
    Divider()
    copyEpisodeName
    shareSection
  }

  // MARK: - Sections

  private var goToShowSection: some View {
    NavigationLink(value: episode.asAppleRSSPodcast) {
      Label("Go to Show", systemImage: "square.stack")
    }
  }

  private func starButton(isStarred: Bool) -> some View {
    Button {
      toggleStar()
    } label: {
      Label(
        isStarred ? "Unstar" : "Star",
        systemImage: isStarred ? "star.fill" : "star"
      )
    }
  }

  private func playedButton(isCompleted: Bool) -> some View {
    Button {
      togglePlayed()
    } label: {
      Label(
        isCompleted ? "Mark as Unplayed" : "Mark as Played",
        systemImage: isCompleted ? "arrow.counterclockwise" : "checkmark.circle"
      )
    }
  }

  private var playNextButton: some View {
    Button {
      addToPlayNext()
    } label: {
      Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
    }
  }

  @ViewBuilder
  private func downloadActions(state: DownloadState) -> some View {
    switch state {
    case .notDownloaded:
      Button {
        startDownload()
      } label: {
        Label("Download", systemImage: "arrow.down.circle")
      }
      .disabled(audioURL == nil)

    case .downloading:
      Button {
        cancelDownload()
      } label: {
        Label("Cancel Download", systemImage: "xmark.circle")
      }

    case .finishing:
      Label("Saving...", systemImage: "arrow.down.circle.dotted")

    case .downloaded:
      Button(role: .destructive) {
        deleteDownload()
      } label: {
        Label("Delete Download", systemImage: "trash")
      }

    case .failed:
      Button {
        startDownload()
      } label: {
        Label("Retry Download", systemImage: "arrow.clockwise")
      }
    }
  }

  private var copyEpisodeName: some View {
    Button {
      PlatformClipboard.string = episodeTitle
    } label: {
      Label("Copy Episode Name", systemImage: "doc.on.doc")
    }
  }

  @ViewBuilder
  private var shareSection: some View {
    if let urlString = episode.episode.trackViewUrl, let url = URL(string: urlString) {
      Button {
        PlatformShareSheet.share(url: url)
      } label: {
        Label("Share Episode", systemImage: "square.and.arrow.up")
      }
    } else if let urlString = audioURL, let url = URL(string: urlString) {
      Button {
        PlatformShareSheet.share(url: url)
      } label: {
        Label("Share Episode", systemImage: "square.and.arrow.up")
      }
    }
  }

  // MARK: - Actions

  private func toggleStar() {
    let key = episodeKey
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )
    if let model = try? modelContext.fetch(descriptor).first {
      model.isStarred.toggle()
    } else {
      let model = EpisodeDownloadModel(
        episodeTitle: episodeTitle,
        podcastTitle: podcastTitle,
        audioURL: audioURL ?? "",
        isStarred: true,
        imageURL: imageURL,
        pubDate: releaseDate
      )
      modelContext.insert(model)
    }
    try? modelContext.save()
  }

  private func togglePlayed() {
    let key = episodeKey
    let descriptor = FetchDescriptor<EpisodeDownloadModel>(
      predicate: #Predicate { $0.id == key }
    )
    if let model = try? modelContext.fetch(descriptor).first {
      model.setCompleted(!model.isCompleted)
    } else {
      let model = EpisodeDownloadModel(
        episodeTitle: episodeTitle,
        podcastTitle: podcastTitle,
        audioURL: audioURL ?? "",
        isCompleted: true,
        imageURL: imageURL,
        pubDate: releaseDate
      )
      modelContext.insert(model)
    }
    try? modelContext.save()
    NotificationCenter.default.post(name: .episodeCompletionChanged, object: nil)
  }

  private func addToPlayNext() {
    guard let audioURL else { return }
    let playbackEpisode = PlaybackEpisode(
      id: episodeKey,
      title: episodeTitle,
      podcastTitle: podcastTitle,
      audioURL: audioURL,
      imageURL: imageURL,
      episodeDescription: episode.episode.description,
      pubDate: releaseDate,
      duration: nil,
      guid: nil
    )
    EnhancedAudioManager.shared.playNext(playbackEpisode)
  }

  private func startDownload() {
    guard let audioURL else { return }
    let info = PodcastEpisodeInfo(
      title: episodeTitle,
      podcastEpisodeDescription: episode.episode.description,
      pubDate: releaseDate,
      audioURL: audioURL,
      imageURL: imageURL,
      duration: nil,
      guid: nil
    )
    DownloadManager.shared.downloadEpisode(
      episode: info,
      podcastTitle: podcastTitle
    )
  }

  private func cancelDownload() {
    DownloadManager.shared.cancelDownload(
      episodeTitle: episodeTitle,
      podcastTitle: podcastTitle
    )
  }

  private func deleteDownload() {
    DownloadManager.shared.deleteDownload(
      episodeTitle: episodeTitle,
      podcastTitle: podcastTitle
    )
  }
}
