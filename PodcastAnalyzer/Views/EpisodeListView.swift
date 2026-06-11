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
      return model.podcastInfo.title
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
    .navigationTitle(navigationTitle)
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
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
        ProgressView("Loading...")
      }
    }
    .task {
      // Initialize ViewModel and refresh in a single task to prevent race conditions
      self.podcastModel = podcastModel
      if viewModel == nil {
        let vm = EpisodeListViewModel(podcastModel: podcastModel, initialFilter: initialFilter)
        vm.setModelContext(modelContext)
        viewModel = vm
      }
      await viewModel?.refreshPodcast()
      await lookupApplePodcastURL(title: podcastModel.podcastInfo.title)
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
      .buttonStyle(.borderedProminent)
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
        await lookupApplePodcastURL(title: existing.podcastInfo.title)
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
    model.isSubscribed = true

    do {
      try modelContext.save()
    } catch {
      loadError = "Failed to subscribe: \(error.localizedDescription)"
    }
  }

  private func unsubscribe() {
    guard let model = podcastModel else { return }

    // Flip the isSubscribed flag to false
    model.isSubscribed = false

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
    List {
      // MARK: - Header Section
      Section {
        headerSection(viewModel: viewModel)
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)

        // MARK: - Filter and Sort Bar
        filterSortBar(viewModel: viewModel)
          .listRowInsets(EdgeInsets())
          .listRowSeparator(.hidden)
          .listRowBackground(Color.clear)
      }

      // MARK: - Episodes List
      Section {
        ForEach(viewModel.filteredEpisodes) { episode in
          EpisodeRowView(
            episode: episode,
            podcastTitle: viewModel.podcastInfo.title,
            fallbackImageURL: viewModel.podcastInfo.imageURL,
            podcastLanguage: viewModel.podcastInfo.language,
            downloadManager: downloadManager,
            episodeModel: viewModel.episodeModels[
              viewModel.makeEpisodeKey(episode)
            ],
            precomputedDownloadState: viewModel.downloadStatesSnapshot[
              viewModel.makeEpisodeKey(episode)
            ],
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
      } header: {
        Text("Episodes (\(viewModel.filteredEpisodeCount))")
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
      }
    }
    .listStyle(.plain)
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
                  try? modelContext.save()
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
              try? modelContext.save()
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
    .searchable(
      text: Binding(
        get: { viewModel.searchText },
        set: { viewModel.searchText = $0 }
      ),
      prompt: "Search episodes"
    )
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
      HTMLTextView(attributedString: attributedString)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: - Header Section

  @ViewBuilder
  private func headerSection(viewModel: EpisodeListViewModel) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        if let url = URL(string: viewModel.podcastInfo.imageURL) {
          CachedAsyncImage(url: url) { image in
               image.resizable().scaledToFit()
          } placeholder: {
               Color.gray
                  .overlay(ProgressView())
          }
          .frame(width: 100, height: 100)
          .clipShape(.rect(cornerRadius: 8))
        } else {
          Color.gray.frame(width: 100, height: 100).clipShape(.rect(cornerRadius: 8))
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(viewModel.podcastInfo.title)
            .font(.headline)

          if !artistName.isEmpty {
            Text(artistName)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          // Language badge
          HStack(spacing: 4) {
            Image(systemName: "globe")
              .font(.system(size: 10))
            Text(
              languageDisplayName(
                for: viewModel.podcastInfo.language
              )
            )
            .font(.caption2)
          }
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.gray.opacity(0.15))
          .clipShape(.rect(cornerRadius: 4))

          // Subscribe / Unsubscribe button
          Button {
            if isSubscribed {
              showUnsubscribeConfirmation = true
            } else {
              subscribe()
            }
          } label: {
            HStack {
              Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle.fill")
              Text(isSubscribed ? "Subscribed" : "Subscribe")
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(isSubscribed ? Color.primary : Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSubscribed ? Color.gray.opacity(0.25) : Color.blue)
            .clipShape(.rect(cornerRadius: 16))
          }
          .buttonStyle(.plain)
          .padding(.top, 4)

          if viewModel.podcastInfo.podcastInfoDescription != nil {
            VStack(alignment: .leading, spacing: 2) {
              descriptionView(for: viewModel)
                .lineLimit(
                  viewModel.isDescriptionExpanded ? nil : 3
                )

              Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                  viewModel.isDescriptionExpanded.toggle()
                }
              }) {
                Text(
                  viewModel.isDescriptionExpanded
                    ? "Show less" : "More"
                )
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 10)
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
    VStack(spacing: 12) {
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
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

          Divider()
            .frame(height: 24)

          Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
              viewModel.sortOldestFirst.toggle()
            }
          }) {
            HStack(spacing: 4) {
              Image(
                systemName: viewModel.sortOldestFirst
                  ? "arrow.up" : "arrow.down"
              )
              .font(.system(size: 12))
              Text(
                viewModel.sortOldestFirst ? "Oldest" : "Newest"
              )
              .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(.primary)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
      }
      .scrollIndicators(.hidden)
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
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
