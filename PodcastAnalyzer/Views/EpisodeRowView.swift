//
//  EpisodeRowView.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/9.
//


import SwiftData
import SwiftUI

#if os(iOS)
import UIKit
#endif

struct EpisodeRowView: View {
  let episode: PodcastEpisodeInfo
  let podcastTitle: String
  let fallbackImageURL: String?
  let podcastLanguage: String
  let downloadManager: DownloadManager
  let episodeModel: EpisodeDownloadModel?
  var showArtwork: Bool = true
  let onToggleStar: () -> Void
  let onDownload: () -> Void
  let onDeleteRequested: () -> Void
  let onTogglePlayed: () -> Void
  /// Optional Apple-Podcasts-style "Remove from Up Next" action.
  /// Nil for rows outside Up Next; the swipe button is hidden when nil.
  let onRemoveFromUpNext: (() -> Void)?

  /// When non-nil, this pre-computed download state is used instead of reading
  /// directly from DownloadManager. Pass this from a parent that already has the
  /// state (e.g. EpisodeListView reads it once per refresh, not on every tick).
  /// This prevents every row from re-rendering on every download progress update.
  let precomputedDownloadState: DownloadState?

  /// Primary initializer for PodcastEpisodeInfo (used in EpisodeListView)
  init(
    episode: PodcastEpisodeInfo,
    podcastTitle: String,
    fallbackImageURL: String?,
    podcastLanguage: String,
    downloadManager: DownloadManager = DownloadManager.shared,
    episodeModel: EpisodeDownloadModel? = nil,
    precomputedDownloadState: DownloadState? = nil,
    showArtwork: Bool = true,
    onToggleStar: @escaping () -> Void,
    onDownload: @escaping () -> Void,
    onDeleteRequested: @escaping () -> Void,
    onTogglePlayed: @escaping () -> Void,
    onRemoveFromUpNext: (() -> Void)? = nil
  ) {
    self.episode = episode
    self.podcastTitle = podcastTitle
    self.fallbackImageURL = fallbackImageURL
    self.podcastLanguage = podcastLanguage
    self.downloadManager = downloadManager
    self.episodeModel = episodeModel
    self.precomputedDownloadState = precomputedDownloadState
    self.showArtwork = showArtwork
    self.onToggleStar = onToggleStar
    self.onDownload = onDownload
    self.onDeleteRequested = onDeleteRequested
    self.onTogglePlayed = onTogglePlayed
    self.onRemoveFromUpNext = onRemoveFromUpNext
  }

  /// Convenience initializer for LibraryEpisode (used in Library views)
  init(
    libraryEpisode: LibraryEpisode,
    downloadManager: DownloadManager = DownloadManager.shared,
    episodeModel: EpisodeDownloadModel? = nil,
    showArtwork: Bool = true,
    onToggleStar: @escaping () -> Void,
    onDownload: @escaping () -> Void,
    onDeleteRequested: @escaping () -> Void,
    onTogglePlayed: @escaping () -> Void,
    onRemoveFromUpNext: (() -> Void)? = nil
  ) {
    self.episode = libraryEpisode.episodeInfo
    self.podcastTitle = libraryEpisode.podcastTitle
    self.fallbackImageURL = libraryEpisode.imageURL
    self.podcastLanguage = libraryEpisode.language
    self.downloadManager = downloadManager
    self.episodeModel = episodeModel
    self.precomputedDownloadState = nil
    self.showArtwork = showArtwork
    self.onToggleStar = onToggleStar
    self.onDownload = onDownload
    self.onDeleteRequested = onDeleteRequested
    self.onTogglePlayed = onTogglePlayed
    self.onRemoveFromUpNext = onRemoveFromUpNext
  }

  @Environment(\.modelContext) private var modelContext
  /// Singleton accessor — only used inside action closures (playAction,
  /// contextMenu.playNext). The reactive playing-indicator subview observes
  /// `isPlaying` / `currentEpisode` itself, so reading `.shared` here does
  /// not register the row as an audio-manager dependency.
  private var audioManager: EnhancedAudioManager { .shared }
  private var transcriptManager: TranscriptManager { .shared }
  private let applePodcastService = ApplePodcastService()
  @State private var shareTask: Task<Void, Never>?
  @State private var cachedPlainDescription: String?
  @State private var hasAIAnalysis = false
  /// Cached transcript-file existence. Computed once in `.onAppear` (and
  /// refreshed when the transcript job for this row completes) so we don't
  /// hit the filesystem on every body evaluation — which for a 50-row list
  /// blocked the main thread during the Library → EpisodeList navigation
  /// transition.
  @State private var hasCaptions = false

  // MARK: - Download state
  //
  // PERFORMANCE: Do NOT read downloadManager.downloadStates here as a computed property.
  // That makes this view a dependency of the @Observable downloadStates dictionary,
  // causing every row to re-render on every download progress tick.
  //
  // Instead, `precomputedDownloadState` is passed from the parent (e.g. EpisodeListView
  // snapshots the state once per row). When nil (Library views with already-downloaded
  // episodes), we fall back to a lazy one-time read via statusChecker.
  //
  // The statusChecker is only used for non-hot-path properties (episodeKey, hasCaptions,
  // playbackURL). It is NOT accessed during body evaluation for download state.

  private var downloadState: DownloadState {
    if let precomputed = precomputedDownloadState { return precomputed }
    return downloadManager.getDownloadState(
      episodeTitle: episode.title,
      podcastTitle: podcastTitle
    )
  }

  private var isDownloaded: Bool {
    if case .downloaded = downloadState { return true }
    return false
  }

  private var episodeKey: String {
    EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episode.title)
  }

  private var playbackURL: String {
    if case .downloaded(let path) = downloadState {
      return URL(fileURLWithPath: path).absoluteString
    }
    return episode.audioURL ?? ""
  }

  /// Used only by `.onChange` to refresh `hasCaptions` when the row's
  /// transcript job finishes. The status chip itself is rendered by an
  /// isolated subview that owns the manager subscription.
  private var transcriptJob: TranscriptJob? {
    transcriptManager.activeJobs[episodeKey]
  }

  private var isStarred: Bool { episodeModel?.isStarred ?? false }
  private var isCompleted: Bool { episodeModel?.isCompleted ?? false }
  private var playbackProgress: Double { episodeModel?.progress ?? 0 }

  private var episodeImageURL: String {
    episode.imageURL ?? fallbackImageURL ?? ""
  }

  // Cache the plain description to avoid regex on every render
  private var plainDescription: String? {
    guard let desc = episode.podcastEpisodeDescription else { return nil }
    let stripped = desc.replacingOccurrences(
      of: "<[^>]+>",
      with: "",
      options: .regularExpression
    )
    .replacingOccurrences(of: "&nbsp;", with: " ")
    .replacingOccurrences(of: "&amp;", with: "&")
    .replacingOccurrences(of: "&lt;", with: "<")
    .replacingOccurrences(of: "&gt;", with: ">")
    .replacingOccurrences(of: "&#39;", with: "'")
    .replacingOccurrences(of: "&quot;", with: "\"")
    .trimmingCharacters(in: .whitespacesAndNewlines)
    return stripped.isEmpty ? nil : stripped
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      NavigationLink(value: EpisodeDetailRoute(
        episode: episode,
        podcastTitle: podcastTitle,
        fallbackImageURL: fallbackImageURL,
        podcastLanguage: podcastLanguage
      )) {
        HStack(alignment: .center, spacing: 12) {
          if showArtwork {
            episodeThumbnail
          }
          episodeInfo
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      bottomStatusBar
    }
    .padding(.vertical, 8)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      trailingSwipeActions
    }
    .swipeActions(edge: .leading, allowsFullSwipe: true) {
      leadingSwipeActions
    }
    .contextMenu {
      contextMenuContent
    }
    .onAppear {
      if cachedPlainDescription == nil {
        cachedPlainDescription = plainDescription
      }
      let checker = EpisodeStatusChecker(
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        audioURL: episode.audioURL
      )
      // Cache disk-dependent status once per appearance rather than per body
      // evaluation. Without this we hit the filesystem for every visible row
      // every time SwiftUI re-renders the list.
      hasCaptions = checker.hasTranscript
      hasAIAnalysis = checker.hasAIAnalysis(in: modelContext)
    }
    .onChange(of: transcriptJob?.status) { _, status in
      // When the transcript job for THIS row finishes, refresh the cached
      // captions flag so the icon appears without needing to leave/return.
      if case .completed = status {
        hasCaptions = true
      }
    }
  }

  @ViewBuilder
  private var episodeThumbnail: some View {
    ZStack(alignment: .bottomTrailing) {
      // Using CachedAsyncImage for better performance
      CachedArtworkImage(urlString: episodeImageURL, size: 90, cornerRadius: 8)

      // Audio-manager observation is isolated inside this subview so the
      // whole row doesn't re-render on every isPlaying / currentTime tick.
      EpisodeRowPlayingIndicator(
        episodeTitle: episode.title,
        podcastTitle: podcastTitle
      )
    }
  }

  private static let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
  }()

  /// Format episode date - relative for today, otherwise abbreviated
  private func formatEpisodeDate(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) {
      return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    } else {
      return date.formatted(date: .abbreviated, time: .omitted)
    }
  }

  @ViewBuilder
  private var episodeInfo: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Date row
      if let date = episode.pubDate {
        Text(formatEpisodeDate(date))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // Title
      Text(episode.title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .lineLimit(3)
        .foregroundStyle(.primary)

      // Description
      if let description = cachedPlainDescription {
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
    }
  }

  @ViewBuilder
  private var bottomStatusBar: some View {
    HStack(spacing: 6) {
      // Play button with progress - uses live audio manager state
      LivePlaybackButton(
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        duration: episodeModel?.duration,
        formattedDuration: episode.formattedDuration,
        lastPlaybackPosition: episodeModel?.lastPlaybackPosition ?? 0,
        playbackProgress: playbackProgress,
        isCompleted: isCompleted,
        onPlay: playAction,
        style: .compact,
        isDisabled: episode.audioURL == nil
      )

      // Download progress
      if case .downloading(let progress) = downloadState {
        HStack(spacing: 2) {
          ProgressView().scaleEffect(0.4)
          Text("\(Int(progress * 100))%").font(.system(size: 9))
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular.tint(.orange), in: .capsule)
      } else if case .finishing = downloadState {
        HStack(spacing: 2) {
          ProgressView().scaleEffect(0.4)
          Text("Saving").font(.system(size: 9))
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassEffect(.regular.tint(.blue), in: .capsule)
      }

      // Status indicators
      HStack(spacing: 4) {
        if isStarred {
          Image(systemName: "star.fill")
            .font(.system(size: 10))
            .foregroundStyle(.yellow)
        }

        if isDownloaded {
          Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.green)
        }

        if hasCaptions {
          Image(systemName: "captions.bubble.fill")
            .font(.system(size: 10))
            .foregroundStyle(.purple)
        } else {
          // Transcript-manager observation is isolated in this subview so
          // the row body doesn't re-render on every transcript progress tick.
          EpisodeRowTranscriptIndicator(episodeKey: episodeKey)
        }

        if hasAIAnalysis {
          Image(systemName: "sparkles")
            .font(.system(size: 10))
            .foregroundStyle(.orange)
        }

        if isCompleted {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 10))
            .foregroundStyle(.green)
        }
      }

      Spacer()

      // Ellipsis menu button
      Menu {
        contextMenuContent
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Episode options")
      .compositingGroup()
      .buttonStyle(.plain)
    }
  }

  @ViewBuilder
  private var contextMenuContent: some View {
    EpisodeMenuActions(
      isStarred: isStarred,
      isCompleted: isCompleted,
      hasLocalAudio: isDownloaded,
      downloadState: downloadState,
      audioURL: episode.audioURL,
      onToggleStar: onToggleStar,
      onTogglePlayed: onTogglePlayed,
      onDownload: onDownload,
      onCancelDownload: {
        downloadManager.cancelDownload(
          episodeTitle: episode.title,
          podcastTitle: podcastTitle
        )
      },
      onDeleteDownload: onDeleteRequested,
      onShare: {
        shareEpisode()
      },
      onPlayNext: {
        guard let audioURL = episode.audioURL else { return }
        let playbackEpisode = PlaybackEpisode(
          id: episodeKey,
          title: episode.title,
          podcastTitle: podcastTitle,
          audioURL: audioURL,
          imageURL: episode.imageURL ?? fallbackImageURL,
          episodeDescription: episode.podcastEpisodeDescription,
          pubDate: episode.pubDate,
          duration: episode.duration,
          guid: episode.guid
        )
        audioManager.playNext(playbackEpisode)
      }
    )
  }

  @ViewBuilder
  private var trailingSwipeActions: some View {
    if let onRemoveFromUpNext {
      Button(role: .destructive, action: onRemoveFromUpNext) {
        Label("Remove", systemImage: "minus.circle")
      }
      .tint(.gray)
    }

    Button(action: onToggleStar) {
      Label(
        isStarred ? "Unstar" : "Star",
        systemImage: isStarred ? "star.slash" : "star.fill"
      )
    }
    .tint(.yellow)

    if isDownloaded {
      Button(role: .destructive, action: onDeleteRequested) {
        Label("Delete", systemImage: "trash")
      }
    } else if case .downloading = downloadState {
      Button(action: {
        downloadManager.cancelDownload(
          episodeTitle: episode.title,
          podcastTitle: podcastTitle
        )
      }) {
        Label("Cancel", systemImage: "xmark.circle")
      }
      .tint(.orange)
    } else if case .finishing = downloadState {
      Button(action: {}) {
        Label("Saving", systemImage: "arrow.down.circle.dotted")
      }
      .tint(.gray)
      .disabled(true)
    } else if episode.audioURL != nil {
      Button(action: onDownload) {
        Label("Download", systemImage: "arrow.down.circle")
      }
      .tint(.blue)
    }
  }

  @ViewBuilder
  private var leadingSwipeActions: some View {
    Button(action: onTogglePlayed) {
      Label(
        isCompleted ? "Unplayed" : "Played",
        systemImage: isCompleted
          ? "arrow.counterclockwise" : "checkmark.circle"
      )
    }
    .tint(.green)
  }

  private func playAction() {
    guard episode.audioURL != nil else { return }

    let imageURL = episode.imageURL ?? fallbackImageURL ?? ""

    let playbackEpisode = PlaybackEpisode(
      id: episodeKey,
      title: episode.title,
      podcastTitle: podcastTitle,
      audioURL: playbackURL,
      imageURL: imageURL,
      episodeDescription: episode.podcastEpisodeDescription,
      pubDate: episode.pubDate,
      duration: episode.duration,
      guid: episode.guid
    )

    let startTime = episodeModel?.lastPlaybackPosition ?? 0
    let useDefaultSpeed = startTime == 0

    audioManager.play(
      episode: playbackEpisode,
      audioURL: playbackURL,
      startTime: startTime,
      imageURL: imageURL,
      useDefaultSpeed: useDefaultSpeed
    )
  }

  private func shareEpisode() {
    shareTask?.cancel()
    shareTask = Task {
      do {
        // Use timeout with task group
        let appleUrl = try await withThrowingTaskGroup(of: String?.self) { group in
          group.addTask {
            try await applePodcastService.getAppleEpisodeLink(
              episodeTitle: episode.title,
              episodeGuid: episode.guid
            )
          }
          group.addTask {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            throw CancellationError()
          }
          let result = try await group.next()!
          group.cancelAll()
          return result
        }
        if !Task.isCancelled {
          shareWithURL(appleUrl ?? episode.audioURL)
        }
      } catch {
        if !Task.isCancelled {
          shareWithURL(episode.audioURL)
        }
      }
    }
  }

  private func shareWithURL(_ urlString: String?) {
    guard let urlString = urlString, let url = URL(string: urlString) else {
      return
    }
    PlatformShareSheet.share(url: url)
  }
}

// MARK: - Transcript Indicator

/// Small chip showing transcript generation progress for this row.
/// Owns the `TranscriptManager.shared.activeJobs` subscription so transcript
/// progress ticks only re-render this view, not the entire row.
private struct EpisodeRowTranscriptIndicator: View {
  let episodeKey: String

  private var transcriptManager: TranscriptManager { .shared }

  private var job: TranscriptJob? {
    transcriptManager.activeJobs[episodeKey]
  }

  var body: some View {
    if let job {
      switch job.status {
      case .downloadingModel(let progress):
        HStack(spacing: 2) {
          ProgressView().scaleEffect(0.35)
          Text("Model")
            .font(.system(size: 8))
            .foregroundStyle(.purple)
          Text("\(Int(progress * 100))%")
            .font(.system(size: 8))
            .foregroundStyle(.purple)
        }
      case .transcribing(let progress):
        HStack(spacing: 2) {
          ProgressView().scaleEffect(0.35)
          Text("\(Int(progress * 100))%")
            .font(.system(size: 8))
            .foregroundStyle(.purple)
        }
      case .queued:
        HStack(spacing: 2) {
          ProgressView().scaleEffect(0.35)
        }
      case .completed, .failed:
        EmptyView()
      }
    }
  }
}

// MARK: - Playing Indicator

/// Tiny overlay that shows the playing / paused glyph when this row's
/// episode is the one loaded in `EnhancedAudioManager`. Extracting it from
/// `EpisodeRowView` is a performance win: only this subview re-renders when
/// `audioManager.isPlaying` or `audioManager.currentEpisode` change, instead
/// of every visible row.
private struct EpisodeRowPlayingIndicator: View {
  let episodeTitle: String
  let podcastTitle: String

  private var audioManager: EnhancedAudioManager { .shared }

  private var isPlayingThisEpisode: Bool {
    guard let currentEpisode = audioManager.currentEpisode else { return false }
    return currentEpisode.title == episodeTitle
      && currentEpisode.podcastTitle == podcastTitle
  }

  var body: some View {
    if isPlayingThisEpisode {
      Image(systemName: audioManager.isPlaying ? "waveform" : "pause.fill")
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(.white)
        .padding(4)
        .glassEffect(.regular.tint(.blue), in: .rect(cornerRadius: 4))
        .padding(4)
    }
  }
}
