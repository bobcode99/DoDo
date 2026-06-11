//
//  MacContentView.swift
//  PodcastAnalyzer
//
//  macOS-specific content view with sidebar navigation (like Apple Podcasts/Spotify)
//

#if os(macOS)
import SwiftData
import SwiftUI

// MARK: - Sidebar Navigation Item

enum MacSidebarItem: String, CaseIterable, Identifiable, Hashable {
  case home = "Home"
  case library = "Library"
  case analysis = "Analysis"
  case search = "Search"
  // Library sub-items with unique identifiers
  case libraryPodcasts = "Library.Podcasts"
  case librarySaved = "Library.Saved"
  case libraryDownloaded = "Library.Downloaded"
  case libraryLatest = "Library.Latest"
  case libraryTranscribing = "Library.Transcribing"

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .home: return "house"
    case .library: return "books.vertical"
    case .analysis: return "sparkles"
    case .search: return "magnifyingglass"
    case .libraryPodcasts: return "square.stack"
    case .librarySaved: return "star.fill"
    case .libraryDownloaded: return "arrow.down.circle.fill"
    case .libraryLatest: return "clock.fill"
    case .libraryTranscribing: return "waveform.badge.plus"
    }
  }

  // Convert to LibrarySubItem if applicable
  var librarySubItem: LibrarySubItem? {
    switch self {
    case .libraryPodcasts: return .podcasts
    case .librarySaved: return .saved
    case .libraryDownloaded: return .downloaded
    case .libraryLatest: return .latest
    default: return nil
    }
  }
}

// MARK: - Library Sub-items

enum LibrarySubItem: String, CaseIterable, Identifiable {
  case podcasts = "Your Podcasts"
  case saved = "Saved"
  case downloaded = "Downloaded"
  case latest = "Latest Episodes"

  var id: String { rawValue }

  var iconName: String {
    switch self {
    case .podcasts: return "square.stack"
    case .saved: return "star.fill"
    case .downloaded: return "arrow.down.circle.fill"
    case .latest: return "clock.fill"
    }
  }
}

// MARK: - Main Content View

struct MacContentView: View {
  // @Observable singletons: use computed properties for read-only access
  private var audioManager: EnhancedAudioManager { .shared }
  private var notificationManager: NotificationNavigationManager { .shared }
  // importManager needs @State because $binding syntax is required for sheet
  @State private var importManager = PodcastImportManager.shared
  @Environment(\.modelContext) private var modelContext

  @State private var selectedSidebarItem: MacSidebarItem? = .home
  @State private var selectedLibrarySubItem: LibrarySubItem? = .podcasts
  @State private var searchText: String = ""
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var showExpandedPlayer = false
  @State private var navigationPath = NavigationPath()

  // For notification navigation
  @State private var notificationEpisode: PodcastEpisodeInfo?
  @State private var notificationPodcastTitle: String = ""
  @State private var notificationImageURL: String?
  @State private var notificationLanguage: String = "en"
  @State private var showNotificationEpisode: Bool = false

  // Friendly playback-blocked alert (offline + no local copy)
  @State private var playbackAlertMessage: String?

  // Track if there's a current episode for mini player
  private var hasCurrentEpisode: Bool {
    audioManager.currentEpisode != nil
  }

  var body: some View {
    @Bindable var importManager = importManager

    ZStack(alignment: .bottom) {
      NavigationSplitView(columnVisibility: $columnVisibility) {
        sidebarContent
          .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
      } detail: {
        mainContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .safeAreaInset(edge: .bottom) {
            if hasCurrentEpisode {
              Color.clear.frame(height: 80)
            }
          }
      }
      .navigationSplitViewStyle(.balanced)

      if hasCurrentEpisode {
        MacMiniPlayerBar(showExpandedPlayer: $showExpandedPlayer)
          .padding(.horizontal, 8)
          .padding(.bottom, 4)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.25), value: hasCurrentEpisode)
    .frame(minWidth: 900, minHeight: 600)
    .sheet(isPresented: $showExpandedPlayer) {
      MacExpandedPlayerView()
    }
    .onAppear { audioManager.restoreLastEpisode() }
    .sheet(isPresented: $importManager.showImportSheet) {
      PodcastImportSheet().frame(minWidth: 400, minHeight: 300)
    }
    .onChange(of: notificationManager.shouldNavigate) { _, shouldNavigate in
      if shouldNavigate, let target = notificationManager.navigationTarget {
        handleNotificationNavigation(target: target)
      }
    }
    .task {
      for await notification in NotificationCenter.default.notifications(
        named: .audioPlaybackUnavailable)
      {
        if let message = notification.userInfo?["message"] as? String {
          playbackAlertMessage = message
        }
      }
    }
    .alert(
      "Can't Play Offline",
      isPresented: Binding(
        get: { playbackAlertMessage != nil },
        set: { if !$0 { playbackAlertMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) { playbackAlertMessage = nil }
    } message: {
      Text(playbackAlertMessage ?? "")
    }
  }

  // MARK: - Sidebar Content

  @ViewBuilder
  private var sidebarContent: some View {
    List(selection: $selectedSidebarItem) {
      Section("Browse") {
        Label("Home", systemImage: "house")
          .tag(MacSidebarItem.home)

        Label {
          Text("Analysis")
        } icon: {
          Image(systemName: "sparkles")
            .foregroundStyle(.purple)
        }
        .tag(MacSidebarItem.analysis)
      }

      Section("Library") {
        Label {
          Text("Your Podcasts")
        } icon: {
          Image(systemName: "square.stack")
            .foregroundStyle(.blue)
        }
        .tag(MacSidebarItem.libraryPodcasts)

        Label {
          Text("Saved")
        } icon: {
          Image(systemName: "star.fill")
            .foregroundStyle(.yellow)
        }
        .tag(MacSidebarItem.librarySaved)

        Label {
          Text("Downloaded")
        } icon: {
          Image(systemName: "arrow.down.circle.fill")
            .foregroundStyle(.green)
        }
        .tag(MacSidebarItem.libraryDownloaded)

        Label {
          Text("Latest Episodes")
        } icon: {
          Image(systemName: "clock.fill")
            .foregroundStyle(.blue)
        }
        .tag(MacSidebarItem.libraryLatest)

        // Shows live counts from TranscriptManager.shared.activeJobs.
        // Isolated subview so progress ticks don't invalidate the whole sidebar.
        TranscribingSidebarLabel()
          .tag(MacSidebarItem.libraryTranscribing)
      }

      Section("Discover") {
        Label("Search", systemImage: "magnifyingglass")
          .tag(MacSidebarItem.search)
      }
    }
    .listStyle(.sidebar)
    .navigationTitle("Podcasts")
    .onChange(of: selectedSidebarItem) { _, newValue in
      // Update selectedLibrarySubItem when a library sub-item is selected
      if let subItem = newValue?.librarySubItem {
        selectedLibrarySubItem = subItem
      }
      // Reset the navigation path so any pushed view (e.g. EpisodeDetail) is
      // dismissed — this ensures onDisappear fires and ViewModels are cleaned up.
      navigationPath = NavigationPath()
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        SettingsLink {
          Image(systemName: "gearshape")
        }
        .help("Settings")
      }
    }
  }

  // MARK: - Main Content

  @ViewBuilder
  private var mainContent: some View {
    NavigationStack(path: $navigationPath) {
      Group {
        switch selectedSidebarItem {
        case .home:
          MacHomeContentView()

        case .libraryPodcasts:
          MacLibraryPodcastsView()
        case .librarySaved:
          MacLibrarySavedView()
        case .libraryDownloaded:
          MacLibraryDownloadedView()
        case .libraryLatest:
          MacLibraryLatestView()
        case .libraryTranscribing:
          TranscriptGenerationProgressOverallView(embedNavigationStack: false)
        case .library:
          // Fallback to podcasts if somehow .library is selected
          MacLibraryPodcastsView()

        case .search:
          MacSearchView()

        case .analysis:
          AnalysisView()

        case .none:
          MacHomeContentView()
        }
      }
      .navigationDestination(for: EpisodeDetailRoute.self) { route in
        MacEpisodeDetailView(
          episode: route.episode,
          podcastTitle: route.podcastTitle,
          fallbackImageURL: route.fallbackImageURL,
          podcastLanguage: route.podcastLanguage ?? "en"
        )
      }
      .navigationDestination(for: EpisodeTranscriptRoute.self) { route in
        MacEpisodeTranscriptView(
          episode: route.episode,
          podcastTitle: route.podcastTitle,
          fallbackImageURL: route.fallbackImageURL,
          podcastLanguage: route.podcastLanguage ?? "en"
        )
      }
      .navigationDestination(for: EpisodeAIAnalysisRoute.self) { route in
        MacEpisodeAIAnalysisView(
          episode: route.episode,
          podcastTitle: route.podcastTitle,
          fallbackImageURL: route.fallbackImageURL,
          podcastLanguage: route.podcastLanguage ?? "en"
        )
      }
      .navigationDestination(for: PodcastBrowseRoute.self) { route in
        if let model = route.podcastModel {
          EpisodeListView(podcastModel: model, initialFilter: route.initialFilter)
        } else {
          EpisodeListView(
            podcastName: route.podcastName,
            podcastArtwork: route.artworkURL,
            artistName: route.artistName,
            collectionId: route.collectionId ?? "",
            applePodcastUrl: route.applePodcastURL,
            initialFilter: route.initialFilter
          )
        }
      }
      .navigationDestination(for: AppleRSSPodcast.self) { podcast in
        EpisodeListView(
          podcastName: podcast.name,
          podcastArtwork: podcast.safeArtworkUrl,
          artistName: podcast.artistName,
          collectionId: podcast.id,
          applePodcastUrl: podcast.url
        )
      }
      .navigationDestination(for: TrendingEpisodeDetailDestination.self) { dest in
        MacEpisodeDetailView(
          episode: dest.asPodcastEpisodeInfo,
          podcastTitle: dest.podcastName,
          fallbackImageURL: dest.podcastArtworkUrl
        )
      }
      // Lets rows inside the Transcribing destination push into the host stack.
      .navigationDestination(for: TranscriptJobRoute.self) { route in
        TranscriptJobEpisodeBridgeView(route: route)
      }
    }
  }

  // MARK: - Notification Navigation

  // Sidebar label for the Transcribing destination. Observes TranscriptManager
  // in isolation so progress ticks don't invalidate the entire sidebar List.
  // The label is always present (so the row is consistently selectable) but
  // its trailing badge only appears when there are jobs to surface.
  private struct TranscribingSidebarLabel: View {
    @State private var manager = TranscriptManager.shared

    private var activeCount: Int {
      var count = 0
      for job in manager.activeJobs.values {
        switch job.status {
        case .queued, .downloadingModel, .transcribing: count += 1
        case .completed, .failed: break
        }
      }
      return count
    }

    var body: some View {
      let count = activeCount
      Label {
        HStack {
          Text("Transcribing")
          Spacer()
          if count > 0 {
            Text("\(count)")
              .font(.caption2.monospacedDigit())
              .padding(.horizontal, 6)
              .padding(.vertical, 1)
              .background(Color.accentColor, in: .capsule)
              .foregroundStyle(.white)
          }
        }
      } icon: {
        Image(systemName: "waveform.badge.plus")
          .foregroundStyle(count > 0 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
          .symbolEffect(.variableColor.iterative, options: .repeat(.continuous), isActive: count > 0)
      }
    }
  }

  private func handleNotificationNavigation(target: NotificationNavigationTarget) {
    if let result = notificationManager.findEpisode(
      podcastTitle: target.podcastTitle,
      episodeTitle: target.episodeTitle
    ) {
      notificationEpisode = result.episode
      notificationPodcastTitle = target.podcastTitle
      notificationImageURL = result.imageURL
      notificationLanguage = result.language
      showNotificationEpisode = true
    }
    notificationManager.clearNavigation()
  }
}

#endif
