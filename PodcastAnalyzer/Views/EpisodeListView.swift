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

// MARK: - Sheets

/// The one modal this screen can be showing. An enum rather than a bool per
/// sheet: they are mutually exclusive, and carrying the podcast in the case
/// means the sheet body never has to unwrap an optional that could be nil by
/// the time it presents.
enum EpisodeListSheet: Identifiable {
  case episodeFilter(PodcastInfoModel)
  case transcribeBackfill(PodcastInfoModel)

  var id: String {
    switch self {
    case .episodeFilter(let model): return "filter-\(model.id)"
    case .transcribeBackfill(let model): return "backfill-\(model.id)"
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
  /// Keeps the error glyph at its designed size while still growing with the
  /// user's text setting — a bare `.system(size: 50)` never moved.
  @ScaledMetric private var errorGlyphSize: Double = 50
  private let source: PodcastSource
  private let initialFilter: EpisodeFilter

  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  private var downloadManager: DownloadManager { .shared }
  @State private var viewModel: EpisodeListViewModel?
  @AppStorage("showEpisodeArtwork") private var showEpisodeArtwork = true
  @State private var episodeToDelete: PodcastEpisodeInfo?
  @State private var showUnsubscribeConfirmation = false
  @State private var applePodcastURL: URL?

  // Browse mode state
  @State private var isLoadingRSS = false
  @State private var loadError: String?
  @State private var podcastModel: PodcastInfoModel?
  @State private var activeSheet: EpisodeListSheet?
  /// A play tapped before the view model finished loading. Held rather than
  /// dropped, so the header's primary action is never a live button that
  /// silently does nothing.
  @State private var pendingPlay = false

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

  /// Author for the hero's meta line.
  ///
  /// Browse mode gets it from Apple's search result; the subscribed path used to
  /// get nothing, which is why the header never showed one. The feed's
  /// `itunes:author` is already parsed and stored — read it rather than leave
  /// the line short.
  private func artistName(viewModel: EpisodeListViewModel) -> String {
    switch source {
    case .model:
      return viewModel.podcastInfo.author ?? ""
    case .browse(_, _, let artist, _, _):
      return artist.isEmpty ? (viewModel.podcastInfo.author ?? "") : artist
    }
  }

  private var isSubscribed: Bool {
    // `podcastModel` is only assigned once `.task` runs, and the header draws
    // before that — read the source directly so "Follow" doesn't flip to
    // "Following" a frame later.
    if let podcastModel { return podcastModel.isSubscribed }
    if case .model(let model) = source { return model.isSubscribed }
    return false
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
    // One List for both phases, not a branch between two of them: the hero row
    // has to keep its identity when the view model lands, or the header the
    // first frame just drew is torn down and rebuilt (tint state included)
    // exactly when the push finishes.
    episodeListContent(viewModel: viewModel)
      .task {
        // Initialize ViewModel and refresh in a single task to prevent race conditions
        self.podcastModel = podcastModel
        if viewModel == nil {
          // Let the push animation land before constructing the view model. Its
          // init decodes the whole `podcastInfo` episode blob on the main actor,
          // and `.task` fires as the view appears — so without this the freeze
          // lands inside the transition. Until then the header draws from the
          // model's denormalized mirrors, which don't touch the blob.
          try? await Task.sleep(for: .milliseconds(300))
          let vm = EpisodeListViewModel(podcastModel: podcastModel, initialFilter: initialFilter)
          vm.setModelContext(modelContext)
          viewModel = vm
          // A play tapped against the placeholder header resolves here, rather
          // than being swallowed by a button that looked enabled.
          if pendingPlay {
            pendingPlay = false
            playTargetEpisode(viewModel: vm)
          }
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

  private func errorView(_ error: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: errorGlyphSize))
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
  private func episodeListContent(viewModel: EpisodeListViewModel?) -> some View {
    // The reader only supplies the top inset (status bar + navigation bar) that
    // the hero has to bleed back over; the List still lays out normally inside.
    GeometryReader { proxy in
      episodeList(viewModel: viewModel, topBleed: proxy.safeAreaInsets.top)
    }
  }

  @ViewBuilder
  private func episodeList(viewModel: EpisodeListViewModel?, topBleed: CGFloat) -> some View {
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
        if let viewModel {
          filterSortBar(viewModel: viewModel)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
      }

      // MARK: - Episodes List
      Section {
        if let viewModel {
          ForEach(viewModel.filteredEpisodes) { episode in
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
              onDeleteRequested: { episodeToDelete = episode },
              onTogglePlayed: {
                viewModel.togglePlayed(for: episode)
              }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
          }
        } else {
          ProgressView("Loading episodes\u{2026}")
            .frame(maxWidth: .infinity)
            .padding(.vertical)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
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
        // Label, not a bare Image: a toolbar Menu renders icon-only anyway, and
        // this is the only thing VoiceOver has to announce it with.
        Menu("More", systemImage: "ellipsis.circle") {
          showActionsMenu
        }
      }
    }
    .refreshable {
      // An explicit pull always makes the round trip; the staleness window is
      // there to throttle the automatic refresh, not the user's gesture.
      await viewModel?.refreshPodcast(force: true)
    }
    .confirmationDialog(
      "Delete Download",
      isPresented: Binding(
        get: { episodeToDelete != nil },
        set: { if !$0 { episodeToDelete = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let episode = episodeToDelete {
          viewModel?.deleteDownload(episode)
        }
        episodeToDelete = nil
      }
      Button("Cancel", role: .cancel) { episodeToDelete = nil }
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
    .sheet(item: $activeSheet) { sheet in
      switch sheet {
      case .episodeFilter(let model):
        PodcastEpisodeFilterView(podcast: model, modelContext: modelContext) {
          // Promote the user's freshly-saved filter into a visible result —
          // switch the chip row to .custom so the list updates immediately.
          // Always assigning (even when already .custom) is intentional:
          // didSet fires unconditionally, so the filter re-evaluates against
          // the new include/exclude/min-duration values.
          withAnimation(.easeInOut(duration: 0.2)) {
            viewModel?.selectedFilter = .custom
          }
        }
      case .transcribeBackfill(let model):
        TranscribeBackfillSheet(
          podcastTitle: model.podcastInfo.title,
          podcastLanguage: model.podcastInfo.language,
          episodes: model.podcastInfo.episodes
        )
      }
    }
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
      descriptionPlaceholder
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

  /// The show-level values the hero draws.
  ///
  /// Taken from the view model once it exists, and from `PodcastInfoModel`'s
  /// denormalized mirrors before that — none of the mirrors decode the episode
  /// blob, so the header renders in the frame the push starts.
  private struct HeroFields {
    var artworkURL = ""
    var title = ""
    var artist = ""
    var episodeCount = 0
    var language = ""
  }

  private func heroFields(viewModel: EpisodeListViewModel?) -> HeroFields {
    if let viewModel {
      return HeroFields(
        artworkURL: viewModel.podcastInfo.imageURL,
        title: viewModel.podcastInfo.title,
        artist: artistName(viewModel: viewModel),
        episodeCount: viewModel.podcastInfo.episodes.count,
        language: languageDisplayName(for: viewModel.podcastInfo.language)
      )
    }
    switch source {
    case .model(let model):
      return HeroFields(
        artworkURL: model.imageURL,
        title: model.title,
        artist: model.feedAuthor,
        episodeCount: model.episodeCount,
        language: model.feedLanguage.isEmpty
          ? "" : languageDisplayName(for: model.feedLanguage)
      )
    case .browse(_, let name, let artist, let artwork, _):
      return HeroFields(artworkURL: artwork, title: name, artist: artist)
    }
  }

  @ViewBuilder
  private func headerSection(viewModel: EpisodeListViewModel?, topBleed: CGFloat) -> some View {
    let fields = heroFields(viewModel: viewModel)
    let target = viewModel?.playTarget
    PodcastHeroHeader(
      artworkURL: fields.artworkURL,
      title: fields.title,
      artist: fields.artist,
      episodeCount: fields.episodeCount,
      language: fields.language,
      isSubscribed: isSubscribed,
      topBleed: topBleed,
      playTitle: target?.isResume == true ? "Resume" : "Latest",
      // Before the view model lands there is no target to test, and every feed
      // with episodes has a playable one — matching the state it resolves to
      // keeps the button from flickering when the two swap.
      canPlay: viewModel == nil ? fields.episodeCount > 0 : target != nil,
      onPlay: {
        if let viewModel {
          playTargetEpisode(viewModel: viewModel)
        } else {
          pendingPlay = true
        }
      },
      onToggleSubscribe: {
        if isSubscribed {
          showUnsubscribeConfirmation = true
        } else {
          subscribe()
        }
      }
    ) {
      if let viewModel {
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
      } else {
        // Reserves the collapsed description's height up front, so the header
        // doesn't grow and shove the list down as the parse lands.
        descriptionPlaceholder
      }
    }
  }

  /// Three reserved lines at the description's own size — used both before the
  /// view model exists and while its HTML parse is in flight.
  private var descriptionPlaceholder: some View {
    Text(verbatim: "\u{2007}\n\u{2007}\n\u{2007}")
      .font(.footnote)
      .lineLimit(3, reservesSpace: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .redacted(reason: .placeholder)
      .accessibilityHidden(true)
  }

  // MARK: - Play Button Target

  private func playTargetEpisode(viewModel: EpisodeListViewModel) {
    guard let episode = viewModel.playTarget?.episode,
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

  /// Contents of the ••• menu.
  @ViewBuilder
  private var showActionsMenu: some View {
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
      Task { await viewModel?.refreshPodcast(force: true) }
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
        if wasOff, podcastModel?.autoTranscribeNewEpisodes == true, let model = podcastModel {
          activeSheet = .transcribeBackfill(model)
        }
      } label: {
        if podcastModel?.autoTranscribeNewEpisodes == true {
          Label("Auto-transcribe: On", systemImage: "waveform.badge.plus")
        } else {
          Label("Auto-transcribe: Off", systemImage: "waveform")
        }
      }

      Button {
        if let model = podcastModel { activeSheet = .episodeFilter(model) }
      } label: {
        Label("Episode Filter\u{2026}", systemImage: "line.3.horizontal.decrease.circle")
      }
    }
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
              .font(.caption.weight(.semibold))
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
        .font(.caption)
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
      do {
        let container = try ModelContainer(
          for: PodcastInfoModel.self, EpisodeDownloadModel.self,
          EpisodeTranscriptModel.self, EpisodeAIAnalysis.self,
          configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.insert(subscribed)
        container.mainContext.insert(unsubscribed)
        return container
      } catch {
        fatalError("Preview container failed to build: \(error)")
      }
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
