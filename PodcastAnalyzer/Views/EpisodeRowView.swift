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
  /// Set once at the app root from UserDefaults, not read per row — see
  /// EpisodeRowAppearance.swift.
  @Environment(\.episodeRowPlayButtonEdge) private var playButtonEdge

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

  /// Transcript / AI-analysis presence, batched by the parent. Both are backed
  /// by SwiftData fetches, so a parent that lists many rows of one podcast
  /// (EpisodeListView) resolves them once for the whole feed and hands the
  /// answer down. nil = no snapshot available (Library views), resolve lazily.
  let precomputedHasTranscript: Bool?
  let precomputedHasAIAnalysis: Bool?

  /// Primary initializer for PodcastEpisodeInfo (used in EpisodeListView)
  init(
    episode: PodcastEpisodeInfo,
    podcastTitle: String,
    fallbackImageURL: String?,
    podcastLanguage: String,
    downloadManager: DownloadManager = DownloadManager.shared,
    episodeModel: EpisodeDownloadModel? = nil,
    precomputedDownloadState: DownloadState? = nil,
    precomputedHasTranscript: Bool? = nil,
    precomputedHasAIAnalysis: Bool? = nil,
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
    self.precomputedHasTranscript = precomputedHasTranscript
    self.precomputedHasAIAnalysis = precomputedHasAIAnalysis
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
    // Library views list episodes across many podcasts, so there is no
    // per-podcast snapshot to hand down — these rows resolve status themselves.
    self.precomputedHasTranscript = nil
    self.precomputedHasAIAnalysis = nil
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
  /// Resolved status. Seeded from the parent's batched snapshots when it has
  /// them; otherwise filled in once from `.onAppear`, same fallback shape as
  /// `precomputedDownloadState`. Both underlying checks are SwiftData fetches,
  /// so resolving them per row cost two fetches for every row that appeared —
  /// twenty on the main thread during a Library → EpisodeList push.
  @State private var resolvedHasCaptions = false
  @State private var resolvedHasAIAnalysis = false

  // OR, not `??`: the snapshot is a point-in-time read, so a transcript that
  // finished while this row was on screen must still win over its stale `false`.
  private var hasCaptions: Bool { resolvedHasCaptions || (precomputedHasTranscript ?? false) }
  private var hasAIAnalysis: Bool { resolvedHasAIAnalysis || (precomputedHasAIAnalysis ?? false) }

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
      // Only when the parent had no batched snapshot to give us — both of
      // these are SwiftData fetches, so a list of one podcast's episodes
      // resolves them once up front instead of twice per appearing row.
      guard precomputedHasTranscript == nil || precomputedHasAIAnalysis == nil else { return }
      let checker = EpisodeStatusChecker(
        episodeTitle: episode.title,
        podcastTitle: podcastTitle,
        audioURL: episode.audioURL
      )
      if precomputedHasTranscript == nil {
        resolvedHasCaptions = checker.hasTranscript
      }
      if precomputedHasAIAnalysis == nil {
        resolvedHasAIAnalysis = checker.hasAIAnalysis(in: modelContext)
      }
    }
    .onChange(of: transcriptJob?.status) { _, status in
      // When the transcript job for THIS row finishes, show the icon without
      // needing to leave and return. Wins over a stale `false` snapshot.
      if case .completed = status {
        resolvedHasCaptions = true
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
      return Formatters.formatDate(date)
    }
  }

  // Every line is reserved whether or not it has content, so all rows are the
  // same height: titles run 1-3 lines, descriptions and dates are often missing
  // entirely, and `cachedPlainDescription` only arrives in `.onAppear` — without
  // a reserved budget each of those resized the row. `reservesSpace` rather than
  // a fixed frame so the budget still scales with Dynamic Type.
  @ViewBuilder
  private var episodeInfo: some View {
    VStack(alignment: .leading, spacing: 6) {
      // Date row
      Text(episode.pubDate.map(formatEpisodeDate) ?? "")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1, reservesSpace: true)

      // Title
      Text(episode.title)
        .font(.subheadline)
        .fontWeight(.semibold)
        .lineLimit(2, reservesSpace: true)
        .foregroundStyle(.primary)

      // Description
      Text(cachedPlainDescription ?? "")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2, reservesSpace: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var bottomStatusBar: some View {
    // The two controls swap ends. Both branches are leaves, so a flip costs one
    // teardown when the user changes the setting — nothing during scroll.
    HStack(spacing: 6) {
      if playButtonEdge == .leading {
        playPill
      } else {
        ellipsisMenu
      }

      // Download progress — live ring (Apple style, no numbers). The ring
      // polls DownloadManager.inFlightProgress itself, so it stays current
      // even between the parent's snapshot rebuilds.
      if case .downloading = downloadState {
        LiveDownloadProgressRing(episodeKey: episodeKey, size: 16, symbol: "arrow.down")
      } else if case .finishing = downloadState {
        ProgressView()
          .scaleEffect(0.5)
          .frame(width: 16, height: 16)
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

      if playButtonEdge == .leading {
        ellipsisMenu
      } else {
        playPill
      }
    }
  }

  /// Play button with progress — uses live audio manager state.
  private var playPill: some View {
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
  }

  private var ellipsisMenu: some View {
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
    .buttonStyle(.plain)
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
      },
      onRemoveFromUpNext: onRemoveFromUpNext
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

    // Completed episodes always restart from 0 — lastPlaybackPosition on a
    // completed episode sits near the end (set by the completion sweep), so
    // using it raw here seeks a freshly-created AVPlayerItem to its own end.
    let startTime = (episodeModel?.isCompleted ?? false) ? 0 : (episodeModel?.lastPlaybackPosition ?? 0)
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
          if let parts = job.partProgress {
            Text("\(min(parts.completed + 1, parts.total))/\(parts.total)")
              .font(.system(size: 8))
              .foregroundStyle(.purple.opacity(0.7))
          }
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
