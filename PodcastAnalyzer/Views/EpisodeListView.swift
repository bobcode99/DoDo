//
//  EpisodeListView.swift
//  PodcastAnalyzer
//
//  Unified view for browsing podcast episodes - works for both subscribed and unsubscribed podcasts.
//

import SwiftData
import SwiftUI

#if os(iOS)
  import UIKit
#endif

// MARK: - Episode Filter Enum

enum EpisodeFilter: String, CaseIterable {
  case all = "All"
  case unplayed = "Unplayed"
  case played = "Played"
  case starred = "Starred"
  case downloaded = "Downloaded"
  case transcript = "Transcript"
  /// User-defined per-podcast filter (include/exclude terms + min-duration)
  /// configured via `PodcastEpisodeFilterView`. Falls back to "show
  /// everything" semantics when no filter fields are set.
  case custom = "Custom"

  var icon: String {
    switch self {
    case .all: return "list.bullet"
    case .unplayed: return "circle"
    case .played: return "checkmark.circle"
    case .starred: return "star.fill"
    case .downloaded: return "arrow.down.circle.fill"
    case .transcript: return "text.bubble"
    case .custom: return "line.3.horizontal.decrease.circle"
    }
  }
}

// MARK: - Podcast Source (subscribed vs browse)

enum PodcastSource {
  case model(PodcastInfoModel)
  case browse(
    collectionId: String, podcastName: String, artistName: String, artworkURL: String,
    applePodcastURL: String?)
}

// MARK: - Episode List View

struct EpisodeListView: View {
  private let source: PodcastSource
  private let initialFilter: EpisodeFilter

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  private var downloadManager: DownloadManager { .shared }
  @State private var viewModel: EpisodeListViewModel?
  @AppStorage("showEpisodeArtwork") private var showEpisodeArtwork = true
  @State private var episodeToDelete: PodcastEpisodeInfo?
  @State private var showDeleteConfirmation = false
  @State private var showUnsubscribeConfirmation = false
  @State private var applePodcastURL: URL?

  // Browse mode state
  @State private var isLoadingRSS = false
  @State private var loadError: String?
  @State private var podcastModel: PodcastInfoModel?
  @State private var showEpisodeFilterSheet = false
  @State private var showTranscribeBackfillSheet = false

  private let applePodcastService = ApplePodcastService()

  // MARK: - Initializers

  /// Initialize with a podcast model (subscribed or browsed)
  init(podcastModel: PodcastInfoModel, initialFilter: EpisodeFilter = .all) {
    self.source = .model(podcastModel)
    self.initialFilter = initialFilter
  }

  /// Initialize for browsing an unsubscribed podcast (will be persisted with isSubscribed=false)
  init(
    podcastName: String,
    podcastArtwork: String,
    artistName: String,
    collectionId: String,
    applePodcastUrl: String?,
    initialFilter: EpisodeFilter = .all
  ) {
    self.source = .browse(
      collectionId: collectionId,
      podcastName: podcastName,
      artistName: artistName,
      artworkURL: podcastArtwork,
      applePodcastURL: applePodcastUrl
    )
    self.initialFilter = initialFilter
  }

  private var navigationTitle: String {
    switch source {
    case .model(let model):
      // Denormalized mirror — avoids decoding the episodes blob on every body
      // pass just to read the title.
      return model.title
    case .browse(_, let name, _, _, _):
      return name
    }
  }

  private var artistName: String {
    switch source {
    case .model:
      return ""
    case .browse(_, _, let artist, _, _):
      return artist
    }
  }

  private var isSubscribed: Bool {
    podcastModel?.isSubscribed ?? false
  }

  private var toolbarPlacement: ToolbarItemPlacement {
    #if os(iOS)
      return .topBarTrailing
    #else
      return .primaryAction
    #endif
  }

  var body: some View {
    Group {
      switch source {
      case .model(let model):
        modelContent(podcastModel: model)
      case .browse:
        browseContent
      }
    }
    // No title in the bar on iOS: the hero header repeats the show name
    // directly below it. macOS keeps it — that title is the window's, not a
    // duplicated row.
    #if os(iOS)
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
    #else
      .navigationTitle(navigationTitle)
    #endif
    .onDisappear {
      // Clean up all resources when view disappears (works for both modes)
      viewModel?.cleanup()
    }
  }

  // MARK: - Model Content (for existing PodcastInfoModel)

  @ViewBuilder
  private func modelContent(podcastModel: PodcastInfoModel) -> some View {
    Group {
      if let vm = viewModel {
        episodeListContent(viewModel: vm)
      } else {
        episodeLoadingView
      }
    }
    .task {
      // Initialize ViewModel and refresh in a single task to prevent race conditions
      self.podcastModel = podcastModel
      if viewModel == nil {
        // Let the push animation land before constructing the view model. Its
        // init decodes the whole `podcastInfo` episode blob on the main actor,
        // and `.task` fires as the view appears — so without this the freeze
        // lands inside the transition. `episodeLoadingView` covers the gap.
        try? await Task.sleep(for: .milliseconds(300))
        let vm = EpisodeListViewModel(podcastModel: podcastModel, initialFilter: initialFilter)
        vm.setModelContext(modelContext)
        viewModel = vm
      }
      await viewModel?.refreshPodcast()
      await lookupApplePodcastURL(title: podcastModel.title)
    }
  }

  // MARK: - Browse Content

  @ViewBuilder
  private var browseContent: some View {
    Group {
      if isLoadingRSS {
        loadingView
      } else if let error = loadError {
        errorView(error)
      } else if let vm = viewModel {
        episodeListContent(viewModel: vm)
      } else {
        loadingView
      }
    }
    .task {
      await loadBrowsePodcast()
    }
  }

  private var loadingView: some View {
    VStack(spacing: 20) {
      if case .browse(_, let name, _, let artwork, _) = source {
        // Use CachedAsyncImage for browse mode artwork
        CachedAsyncImage(url: URL(string: artwork.replacingOccurrences(of: "100x100", with: "300x300"))) { image in
             image.resizable().scaledToFit()
        } placeholder: {
            Color.gray
        }
        .frame(width: 150, height: 150)
        .clipShape(.rect(cornerRadius: 12))

        Text(name)
          .font(.headline)
      }

      ProgressView("Loading episodes...")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Centered, full-frame loading placeholder shown while the view model is
  /// still being built — avoids the abrupt top-left spinner so navigating in
  /// reads as a smooth transition.
  private var episodeLoadingView: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.2)
      Text("Loading episodes\u{2026}")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func errorView(_ error: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 50))
        .foregroundStyle(.orange)

      Text("Unable to load podcast")
        .font(.headline)

      Text(error)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)

      Button("Try Again") {
        Task { await loadBrowsePodcast() }
      }
      .buttonStyle(.accentProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func loadBrowsePodcast() async {
    guard case .browse(let collectionId, let podcastName, _, _, let appleURL) = source else {
      return
    }

    isLoadingRSS = true
    loadError = nil

    // Set Apple URL if provided
    if let urlStr = appleURL, let url = URL(string: urlStr) {
      applePodcastURL = url
    }

    // Check if this podcast already exists in SwiftData (subscribed or browsed before)
    let existingModel = findExistingPodcast(podcastName: podcastName)
    if let existing = existingModel {
      // Use existing model
      self.podcastModel = existing
      let vm = EpisodeListViewModel(podcastModel: existing)
      vm.setModelContext(modelContext)
      self.viewModel = vm

      if applePodcastURL == nil {
        await lookupApplePodcastURL(title: existing.title)
      }

      isLoadingRSS = false
      return
    }

    // Look up RSS URL from Apple
    do {
      guard let podcast = try await applePodcastService.lookupPodcast(collectionId: collectionId),
        let feedUrl = podcast.feedUrl
      else {
        throw URLError(.badServerResponse)
      }

      // Fetch RSS with caching
      let info = try await RSSCacheService.shared.fetchPodcast(from: feedUrl)

      // Persist to SwiftData with isSubscribed = false (browsed podcast)
      let model = PodcastInfoModel(podcastInfo: info, lastUpdated: Date(), isSubscribed: false)
      modelContext.insert(model)
      try modelContext.save()

      self.podcastModel = model
      let vm = EpisodeListViewModel(podcastModel: model)
      vm.setModelContext(modelContext)
      self.viewModel = vm

      // Lookup Apple URL if not provided
      if applePodcastURL == nil {
        await lookupApplePodcastURL(title: info.title)
      }

      isLoadingRSS = false
    } catch {
      loadError = error.localizedDescription
      isLoadingRSS = false
    }
  }

  private func findExistingPodcast(podcastName: String) -> PodcastInfoModel? {
    let descriptor = FetchDescriptor<PodcastInfoModel>(
      predicate: #Predicate { $0.title == podcastName }
    )
    return try? modelContext.fetch(descriptor).first
  }

  private func subscribe() {
    guard let model = podcastModel else { return }

    // Just flip the isSubscribed flag
    model.setSubscribed(true)

    do {
      try modelContext.save()
    } catch {
      loadError = "Failed to subscribe: \(error.localizedDescription)"
    }
  }

  private func unsubscribe() {
    guard let model = podcastModel else { return }

    // Flip the isSubscribed flag to false
    model.setSubscribed(false)

    do {
      try modelContext.save()
      // Navigate back after unsubscribing
      dismiss()
    } catch {
      loadError = "Failed to unsubscribe: \(error.localizedDescription)"
    }
  }

  // MARK: - Episode List Content

  @ViewBuilder
  private func episodeListContent(viewModel: EpisodeListViewModel) -> some View {
    // The reader only supplies the top inset (status bar + navigation bar) that
    // the hero has to bleed back over; the List still lays out normally inside.
    GeometryReader { proxy in
      episodeList(viewModel: viewModel, topBleed: proxy.safeAreaInsets.top)
    }
  }

  @ViewBuilder
  private func episodeList(viewModel: EpisodeListViewModel, topBleed: CGFloat) -> some View {
    List {
      // MARK: - Header Section
      Section {
        headerSection(viewModel: viewModel, topBleed: topBleed)
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)

        // A plain row, not the episode section's `header:`. As a header a plain
        // List pins it, so the chips stayed parked under the navigation bar
        // while the backlog ran past underneath; here the whole screen scrolls
        // as one page and the filters leave with the hero.
        filterSortBar(viewModel: viewModel)
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
      }

      // MARK: - Episodes List
      Section {
        ForEach(viewModel.displayedEpisodes) { episode in
          let key = viewModel.makeEpisodeKey(episode)
          EpisodeRowView(
            episode: episode,
            podcastTitle: viewModel.podcastInfo.title,
            fallbackImageURL: viewModel.podcastInfo.imageURL,
            podcastLanguage: viewModel.podcastInfo.language,
            downloadManager: downloadManager,
            episodeModel: viewModel.episodeModels[key],
            precomputedDownloadState: viewModel.downloadStatesSnapshot[key],
            precomputedHasTranscript: viewModel.transcriptKeys.contains(key),
            precomputedHasAIAnalysis: episode.audioURL.map {
              viewModel.aiAnalysisAudioURLs.contains($0)
            } ?? false,
            showArtwork: showEpisodeArtwork,
            onToggleStar: {
              viewModel.toggleStar(for: episode)
            },
            onDownload: { viewModel.downloadEpisode(episode) },
            onDeleteRequested: {
              episodeToDelete = episode
              showDeleteConfirmation = true
            },
            onTogglePlayed: {
              viewModel.togglePlayed(for: episode)
            }
          )
          .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }

        // "Show All (N)" footer — only the latest `initialEpisodeDisplayCount`
        // episodes render until the user opts into the full backlog.
        if viewModel.hasMoreEpisodesToShow {
          showAllButton(viewModel: viewModel)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
            .listRowSeparator(.hidden)
        }
      }
    }
    .listStyle(.plain)
    #if os(iOS)
    .listSectionSpacing(0)
    // Let the hero gradient run behind the back/••• row instead of stopping at
    // an opaque system bar just below it.
    .toolbarBackground(.hidden, for: .navigationBar)
    #endif
    .toolbar {
      ToolbarItem(placement: toolbarPlacement) {
        Menu {
          if let url = applePodcastURL {
            Link(destination: url) {
              Label("View on Apple Podcasts", systemImage: "link")
            }

            Divider()
          }

          if isSubscribed {
            Button(role: .destructive) {
              showUnsubscribeConfirmation = true
            } label: {
              Label("Unsubscribe", systemImage: "minus.circle")
            }
          } else {
            Button(action: subscribe) {
              Label("Subscribe", systemImage: "plus.circle")
            }
          }

          Divider()

          Button(action: {
            Task { await viewModel.refreshPodcast() }
          }) {
            Label(
              "Refresh Episodes",
              systemImage: "arrow.clockwise"
            )
          }

          if podcastModel != nil && isSubscribed {
            Divider()

            Menu {
              ForEach(AutoDownloadSetting.allCases, id: \.rawValue) { setting in
                Button {
                  podcastModel?.autoDownloadSetting = setting.rawValue
                  modelContext.saveOrLog()
                } label: {
                  if podcastModel?.autoDownloadSetting == setting.rawValue {
                    Label(setting.displayName, systemImage: "checkmark")
                  } else {
                    Text(setting.displayName)
                  }
                }
              }
            } label: {
              let current = AutoDownloadSetting(rawValue: podcastModel?.autoDownloadSetting ?? "") ?? .inheritGlobal
              Label("Auto Download: \(current.displayName)", systemImage: "arrow.down.circle")
            }

            Button {
              let wasOff = podcastModel?.autoTranscribeNewEpisodes != true
              podcastModel?.autoTranscribeNewEpisodes.toggle()
              modelContext.saveOrLog()
              if wasOff && podcastModel?.autoTranscribeNewEpisodes == true {
                showTranscribeBackfillSheet = true
              }
            } label: {
              if podcastModel?.autoTranscribeNewEpisodes == true {
                Label("Auto-transcribe: On", systemImage: "waveform.badge.plus")
              } else {
                Label("Auto-transcribe: Off", systemImage: "waveform")
              }
            }

            Button {
              showEpisodeFilterSheet = true
            } label: {
              Label("Episode Filter\u{2026}", systemImage: "line.3.horizontal.decrease.circle")
            }
          }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
    .refreshable {
      await viewModel.refreshPodcast()
    }
    .confirmationDialog(
      "Delete Download",
      isPresented: $showDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let episode = episodeToDelete {
          viewModel.deleteDownload(episode)
        }
        episodeToDelete = nil
      }
      Button("Cancel", role: .cancel) {
        episodeToDelete = nil
      }
    } message: {
      Text(
        "Are you sure you want to delete this downloaded episode? You can download it again later."
      )
    }
    .confirmationDialog(
      "Unsubscribe from Podcast",
      isPresented: $showUnsubscribeConfirmation,
      titleVisibility: .visible
    ) {
      Button("Unsubscribe", role: .destructive) {
        unsubscribe()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Are you sure you want to unsubscribe from this podcast? Downloaded episodes will remain available."
      )
    }
    .sheet(isPresented: $showEpisodeFilterSheet) {
      if let model = podcastModel {
        PodcastEpisodeFilterView(podcast: model, modelContext: modelContext) {
          // Promote the user's freshly-saved filter into a visible result —
          // switch the chip row to .custom so the list updates immediately.
          // Always assigning (even when already .custom) is intentional:
          // didSet fires unconditionally, so the filter re-evaluates against
          // the new include/exclude/min-duration values.
          withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.selectedFilter = .custom
          }
        }
      }
    }
    .sheet(isPresented: $showTranscribeBackfillSheet) {
      if let model = podcastModel {
        TranscribeBackfillSheet(
          podcastTitle: model.podcastInfo.title,
          podcastLanguage: model.podcastInfo.language,
          episodes: model.podcastInfo.episodes
        )
      }
    }
  }

  /// Footer row that reveals the full episode backlog. Tapping flips the view
  /// model's window flag; the List then materializes the remaining rows.
  @ViewBuilder
  private func showAllButton(viewModel: EpisodeListViewModel) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.25)) {
        viewModel.isShowingAllEpisodes = true
      }
    } label: {
      HStack(spacing: 6) {
        Spacer()
        Text("Show All (\(viewModel.filteredEpisodes.count))")
          .font(.subheadline)
          .fontWeight(.semibold)
        Image(systemName: "chevron.down")
          .font(.caption)
        Spacer()
      }
      .foregroundStyle(.blue)
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  // MARK: - Apple Podcast Lookup

  private func lookupApplePodcastURL(title: String) async {
    let cacheKey = "applePodcastURL_\(title.lowercased())"
    if let cached = UserDefaults.standard.string(forKey: cacheKey),
       let url = URL(string: cached) {
      applePodcastURL = url
      return
    }
    do {
      let podcasts = try await applePodcastService.searchPodcasts(term: title, limit: 5)
      if let match = podcasts.first(where: {
        $0.collectionName.lowercased() == title.lowercased()
      }) ?? podcasts.first {
        let urlString = "https://podcasts.apple.com/podcast/id\(match.collectionId)"
        applePodcastURL = URL(string: urlString)
        UserDefaults.standard.set(urlString, forKey: cacheKey)
      }
    } catch {
      // Silently fail - Apple URL is optional
    }
  }

  @ViewBuilder
  private func descriptionView(for viewModel: EpisodeListViewModel) -> some View {
    switch viewModel.descriptionContent {
    case .loading:
      ProgressView()
        .frame(maxWidth: .infinity, alignment: .center)
    case .empty:
      Text("No description available.")
        .foregroundStyle(.secondary)
        .font(.caption)
    case .parsed(let attributedString):
      // Collapsed height comes from HTMLTextView's own parameter: `.lineLimit()`
      // is a Text modifier and the text view it renders through ignores it.
      HTMLTextView(
        attributedString: attributedString,
        lineLimit: viewModel.isDescriptionExpanded ? nil : 3
      )
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - Header Section

  @ViewBuilder
  private func headerSection(viewModel: EpisodeListViewModel, topBleed: CGFloat) -> some View {
    let target = playTarget(viewModel: viewModel)
    PodcastHeroHeader(
      artworkURL: viewModel.podcastInfo.imageURL,
      title: viewModel.podcastInfo.title,
      artist: artistName,
      episodeCount: viewModel.podcastInfo.episodes.count,
      language: languageDisplayName(for: viewModel.podcastInfo.language),
      isSubscribed: isSubscribed,
      topBleed: topBleed,
      playTitle: target?.isResume == true ? "Resume" : "Latest",
      canPlay: target != nil,
      onPlay: { playTargetEpisode(viewModel: viewModel) },
      onToggleSubscribe: {
        if isSubscribed {
          showUnsubscribeConfirmation = true
        } else {
          subscribe()
        }
      }
    ) {
      if viewModel.podcastInfo.podcastInfoDescription != nil {
        VStack(alignment: .leading, spacing: 2) {
          descriptionView(for: viewModel)

          Button {
            withAnimation(.easeInOut(duration: 0.2)) {
              viewModel.isDescriptionExpanded.toggle()
            }
          } label: {
            Text(viewModel.isDescriptionExpanded ? "Show less" : "More")
              .font(.caption)
              .fontWeight(.medium)
              .foregroundStyle(.blue)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  // MARK: - Play Button Target

  /// What the header's play button acts on: the episode the user last listened
  /// to in this show, falling back to the newest one when nothing here has been
  /// played yet. Independent of the chip filter and the sort direction.
  ///
  /// Recency is the later of `progressUpdatedAt` and `lastPlayedDate`. The
  /// first moves on every playback-position write, so it catches an episode
  /// left half-finished; the second only moves on completion, but legacy rows
  /// may carry just that one.
  private func playTarget(viewModel: EpisodeListViewModel)
    -> (episode: PodcastEpisodeInfo, isResume: Bool)?
  {
    let playable = viewModel.podcastInfo.episodes.filter { $0.audioURL != nil }

    let lastListened =
      playable
      .compactMap { episode -> (PodcastEpisodeInfo, Date)? in
        guard let model = viewModel.episodeModels[viewModel.makeEpisodeKey(episode)],
          let stamp = [model.progressUpdatedAt, model.lastPlayedDate].compactMap({ $0 }).max()
        else { return nil }
        return (episode, stamp)
      }
      .max { $0.1 < $1.1 }?
      .0

    if let lastListened { return (lastListened, true) }

    return playable
      .max { ($0.pubDate ?? .distantPast) < ($1.pubDate ?? .distantPast) }
      .map { ($0, false) }
  }

  private func playTargetEpisode(viewModel: EpisodeListViewModel) {
    guard let episode = playTarget(viewModel: viewModel)?.episode,
      let audioURL = episode.audioURL
    else { return }

    let podcastTitle = viewModel.podcastInfo.title
    let key = viewModel.makeEpisodeKey(episode)
    let model = viewModel.episodeModels[key]
    let imageURL = episode.imageURL ?? viewModel.podcastInfo.imageURL

    // Prefer the downloaded file, same as a row's play button does.
    let state = downloadManager.getDownloadState(
      episodeTitle: episode.title,
      podcastTitle: podcastTitle
    )
    let playbackURL: String
    if case .downloaded(let path) = state {
      playbackURL = URL(fileURLWithPath: path).absoluteString
    } else {
      playbackURL = audioURL
    }

    // A completed episode restarts: its saved position sits at the very end,
    // so seeking a fresh player item there would stop it immediately.
    let startTime = (model?.isCompleted ?? false) ? 0 : (model?.lastPlaybackPosition ?? 0)

    EnhancedAudioManager.shared.play(
      episode: PlaybackEpisode(
        id: key,
        title: episode.title,
        podcastTitle: podcastTitle,
        audioURL: playbackURL,
        imageURL: imageURL,
        episodeDescription: episode.podcastEpisodeDescription,
        pubDate: episode.pubDate,
        duration: episode.duration,
        guid: episode.guid
      ),
      audioURL: playbackURL,
      startTime: startTime,
      imageURL: imageURL,
      useDefaultSpeed: startTime == 0
    )
  }

  /// Convert language code to display name
  private func languageDisplayName(for code: String) -> String {
    let locale = Locale(identifier: code)
    if let name = locale.localizedString(forLanguageCode: code) {
      return name.capitalized
    }
    return code.uppercased()
  }

  @ViewBuilder
  private func filterSortBar(viewModel: EpisodeListViewModel) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ScrollView(.horizontal) {
        HStack(spacing: 7) {
          ForEach(EpisodeFilter.allCases, id: \.self) { filter in
            FilterChip(
              title: filter.rawValue,
              icon: filter.icon,
              isSelected: viewModel.selectedFilter == filter
            ) {
              withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.selectedFilter = filter
              }
            }
          }
        }
        .padding(.horizontal, 16)
      }
      .scrollIndicators(.hidden)

      // "Episodes (N)" and the sort toggle share one row, as in the design —
      // the count is the section label and the direction is its only control.
      HStack {
        Text("Episodes (\(viewModel.filteredEpisodes.count))")
          .font(.headline)
          .foregroundStyle(.primary)

        Spacer()

        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.sortOldestFirst.toggle()
          }
        } label: {
          HStack(spacing: 3) {
            Text(viewModel.sortOldestFirst ? "Oldest" : "Newest")
              .font(.subheadline)
              .fontWeight(.semibold)
            Image(systemName: viewModel.sortOldestFirst ? "arrow.up" : "arrow.down")
              .font(.system(size: 11, weight: .semibold))
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 16)
    }
    .padding(.top, 8)
    .padding(.bottom, 8)
    .background(.bar)
  }
}


// MARK: - Filter Chip Component

struct FilterChip: View {
  let title: String
  let icon: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      chipLabel
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var chipLabel: some View {
    let content = HStack(spacing: 4) {
      Image(systemName: icon)
        .font(.system(size: 12))
      Text(title)
        .font(.caption)
        .fontWeight(isSelected ? .semibold : .regular)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)

    if isSelected {
      content
        .background(Color.blue)
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 16))
    } else {
      content
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
  }
}

// MARK: - Previews

#if DEBUG

  /// Sample store for the previews.
  ///
  /// The view reads its podcast through `@Environment(\.modelContext)`, so the
  /// model has to live in a container the preview installs — a bare
  /// `PodcastInfoModel(...)` renders an empty screen.
  @MainActor
  private enum EpisodeListPreviewData {
    static let episodes: [PodcastEpisodeInfo] = (1...14).map { index in
      PodcastEpisodeInfo(
        title: "Episode \(index): \(titles[(index - 1) % titles.count])",
        podcastEpisodeDescription:
          "Maya and Ravi dig into what shipped this week, what broke, and the one "
          + "decision they'd take back.",
        // Weekly, newest first, so the sort toggle has something to reorder.
        pubDate: Calendar.current.date(byAdding: .day, value: -7 * index, to: .now),
        audioURL: "https://example.com/ep\(index).mp3",
        duration: 1800 + index * 240,
        guid: "preview-episode-\(index)"
      )
    }

    private static let titles = [
      "The On-Device AI Revolution", "Why Your Build Is Slow", "Shipping on a Friday",
      "The Cost of a Free Tier", "Reading the Crash Log", "Everything Is a Cache",
      "Nobody Reads the Docs",
    ]

    static let info = PodcastInfo(
      title: "Signal & Noise",
      description:
        "A weekly conversation about the software people actually ship — the "
        + "trade-offs, the outages, and the parts nobody writes a blog post about. "
        + "Long enough to need the More button.",
      episodes: episodes,
      rssUrl: "https://example.com/feed.xml",
      imageURL: "https://example.com/artwork.jpg",
      language: "en",
      author: "Maya Okonkwo"
    )

    // `lastUpdated: .now` keeps `refreshPodcast()` inside its 30-minute
    // staleness guard, so the preview never reaches for the network.
    static let subscribed = PodcastInfoModel(podcastInfo: info, lastUpdated: .now)
    static let unsubscribed = PodcastInfoModel(
      podcastInfo: info, lastUpdated: .now, isSubscribed: false)

    // The view model fetches downloads, transcripts, and analyses alongside the
    // podcast, so all four belong in the schema — a container that only knows
    // PodcastInfoModel makes those fetches fail.
    static let container: ModelContainer = {
      let container = try! ModelContainer(
        for: PodcastInfoModel.self, EpisodeDownloadModel.self,
        EpisodeTranscriptModel.self, EpisodeAIAnalysis.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
      )
      container.mainContext.insert(subscribed)
      container.mainContext.insert(unsubscribed)
      return container
    }()
  }

  #Preview("Subscribed") {
    NavigationStack {
      EpisodeListView(podcastModel: EpisodeListPreviewData.subscribed)
    }
    .modelContainer(EpisodeListPreviewData.container)
  }

  #Preview("Not subscribed") {
    NavigationStack {
      EpisodeListView(podcastModel: EpisodeListPreviewData.unsubscribed)
    }
    .modelContainer(EpisodeListPreviewData.container)
  }

  /// Starred is empty in the sample data — this is the filtered-to-nothing state.
  #Preview("Starred filter") {
    NavigationStack {
      EpisodeListView(podcastModel: EpisodeListPreviewData.subscribed, initialFilter: .starred)
    }
    .modelContainer(EpisodeListPreviewData.container)
  }

  #Preview("Filter chips") {
    ScrollView(.horizontal) {
      HStack(spacing: 7) {
        ForEach(EpisodeFilter.allCases, id: \.self) { filter in
          FilterChip(title: filter.rawValue, icon: filter.icon, isSelected: filter == .unplayed) {}
        }
      }
      .padding()
    }
  }

#endif
