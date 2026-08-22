//
//  ContentView.swift
//  PodcastAnalyzer
//
//

import SwiftData
import SwiftUI

struct ContentView: View {
  var body: some View {
    #if os(iOS)
    iOSContentView()
      .episodeRowAppearance()
      .appAccentColor()
    #else
    MacContentView()
      .episodeRowAppearance()
      .appAccentColor()
    #endif
  }
}

// MARK: - iOS Content View

#if os(iOS)
struct iOSContentView: View {
  // Access singletons directly without @State to avoid unnecessary observation overhead
  private var audioManager: EnhancedAudioManager { .shared }
  // importManager needs @State because $binding syntax is required for sheet
  @State private var importManager = PodcastImportManager.shared
  private var notificationManager: NotificationNavigationManager { .shared }
  @Environment(\.modelContext) private var modelContext

  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

  @State private var coordinator = TabNavigationCoordinator()
  /// Transient playback/queue problem to surface. Carries its own title so one
  /// alert can serve every such notification instead of stacking a modifier per
  /// message kind.
  @State private var playbackAlert: (title: String, message: String)?

  var body: some View {
    // `visibleTab` is driven by TabView's own selection rather than by an
    // `.onAppear` on each tab's root. Those onAppears wrote to `coordinator`
    // — the same object whose routers back every NavigationStack path binding
    // here — from inside the tab-switch update pass, so SwiftUI logged
    // "Update NavigationRequestObserver tried to update multiple times per
    // frame". Selection is also the more accurate signal: onAppear reports
    // "last tab whose content was built", which is not necessarily the tab the
    // user is on, and `activeRouter` would then push onto the wrong stack.
    TabView(selection: $coordinator.visibleTab) {
      Tab(Constants.homeString, systemImage: Constants.homeIconName, value: TabIdentifier.home) {
        NavigationStack(path: $coordinator.homeRouter.path) {
          HomeView()
            .navigationDestinations()
        }
      }

      Tab(Constants.libraryString, systemImage: Constants.libraryIconName, value: TabIdentifier.library) {
        NavigationStack(path: $coordinator.libraryRouter.path) {
          LibraryView()
            .navigationDestinations()
        }
      }

      Tab(Constants.analysisString, systemImage: Constants.analysisIconName, value: TabIdentifier.analysis) {
        NavigationStack(path: $coordinator.analysisRouter.path) {
          AnalysisView()
            .navigationDestinations()
        }
      }

      Tab(Constants.settingsString, systemImage: Constants.settingsIconName, value: TabIdentifier.settings) {
        NavigationStack(path: $coordinator.settingsRouter.path) {
          SettingsView()
            .navigationDestinations()
        }
      }

      Tab(value: TabIdentifier.search, role: .search) {
        NavigationStack(path: $coordinator.searchRouter.path) {
          PodcastSearchView()
            .navigationDestinations()
        }
      }
    }
    .environment(\.tabNavigationCoordinator, coordinator)
    .tabViewBottomAccessory {
      MiniPlayerBar()
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .onAppear {
      // Restore last played episode on app launch
      audioManager.restoreLastEpisode()
      // Ensure model context is available early (before the async task in PodcastAnalyzerApp)
      notificationManager.setModelContext(modelContext)
    }
    .sheet(isPresented: $importManager.showImportSheet) {
      PodcastImportSheet()
    }
    .fullScreenCover(isPresented: Binding(
      get: { !hasCompletedOnboarding },
      set: { if !$0 { hasCompletedOnboarding = true } }
    )) {
      OnboardingView()
    }
    .onChange(of: notificationManager.shouldNavigate) { _, shouldNavigate in
      if shouldNavigate, let target = notificationManager.navigationTarget {
        handleNotificationNavigation(target: target)
      }
    }
    .onChange(of: coordinator.homeRouter.path.count) { oldCount, newCount in
      // Clear deep link tracker when user navigates back so future widget taps work
      if newCount < oldCount {
        coordinator.lastDeepLinkedEpisodeRouteID = nil
      }
    }
    .task {
      // Surface "no network + no local copy" refusals from EnhancedAudioManager
      // as an in-app alert so users don't see the system "Cellular Data Is
      // Turned Off" prompt that AVPlayer would otherwise trigger.
      for await notification in NotificationCenter.default.notifications(
        named: .audioPlaybackUnavailable)
      {
        if let message = notification.userInfo?["message"] as? String {
          playbackAlert = (title: "Can't Play Offline", message: message)
        }
      }
    }
    .task {
      // Adding to a full queue used to no-op silently, which reads as a broken
      // menu item rather than a limit.
      for await notification in NotificationCenter.default.notifications(
        named: .queueLimitReached)
      {
        if let message = notification.userInfo?["message"] as? String {
          playbackAlert = (title: "Queue Is Full", message: message)
        }
      }
    }
    .alert(
      playbackAlert?.title ?? "",
      isPresented: Binding(
        get: { playbackAlert != nil },
        set: { if !$0 { playbackAlert = nil } }
      )
    ) {
      Button("OK", role: .cancel) { playbackAlert = nil }
    } message: {
      Text(playbackAlert?.message ?? "")
    }
  }

  private func handleNotificationNavigation(target: NotificationNavigationTarget) {
    let route: EpisodeDetailRoute
    // Prefer lookup by audioURL (unique key) so we always get the full episode
    // including description, transcript, and AI analysis — even for non-ASCII titles.
    if !target.audioURL.isEmpty,
       let result = notificationManager.findEpisodeByAudioURL(target.audioURL) {
      route = EpisodeDetailRoute(
        episode: result.episode,
        podcastTitle: result.podcastTitle,
        fallbackImageURL: result.imageURL,
        podcastLanguage: result.language
      )
    } else if let result = notificationManager.findEpisode(
      podcastTitle: target.podcastTitle,
      episodeTitle: target.episodeTitle
    ) {
      route = EpisodeDetailRoute(
        episode: result.episode,
        podcastTitle: target.podcastTitle,
        fallbackImageURL: result.imageURL,
        podcastLanguage: result.language
      )
    } else {
      // Episode not found in SwiftData — use data from the current playback episode
      // (restored from UserDefaults) so we still have the description and metadata.
      let currentEp = EnhancedAudioManager.shared.currentEpisode
      let episode = PodcastEpisodeInfo(
        title: target.episodeTitle,
        podcastEpisodeDescription: currentEp?.episodeDescription,
        pubDate: currentEp?.pubDate,
        audioURL: target.audioURL.isEmpty ? nil : target.audioURL,
        imageURL: target.imageURL.isEmpty ? nil : target.imageURL,
        duration: currentEp?.duration,
        guid: currentEp?.guid
      )
      route = EpisodeDetailRoute(
        episode: episode,
        podcastTitle: target.podcastTitle,
        fallbackImageURL: target.imageURL.isEmpty ? nil : target.imageURL,
        podcastLanguage: target.language
      )
    }

    // Skip if the same episode detail is already the most recent deep-linked route
    // This prevents stacking duplicate screens when the user taps the widget repeatedly
    if coordinator.lastDeepLinkedEpisodeRouteID == route.id {
      notificationManager.clearNavigation()
      return
    }

    coordinator.lastDeepLinkedEpisodeRouteID = route.id
    coordinator.activeRouter.push(route)
    notificationManager.clearNavigation()
  }

}
#endif

// MARK: - Podcast Import Sheet

struct PodcastImportSheet: View {
  @Bindable private var importManager = PodcastImportManager.shared
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        if importManager.isImporting {
          // Progress view
          VStack(spacing: 16) {
            ProgressView(value: importManager.importProgress)
              .progressViewStyle(.linear)
              .padding(.horizontal)

            Text(importManager.importStatus)
              .font(.subheadline)
              .foregroundStyle(.secondary)

            ProgressView()
              .scaleEffect(1.5)
              .padding(.top, 20)
          }
          .padding()
        } else if let results = importManager.importResults {
          // Results view
          VStack(spacing: 20) {
            Image(systemName: results.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
              .font(.system(size: 60))
              .foregroundStyle(results.failed == 0 ? .green : .orange)

            Text("Import Complete")
              .font(.title2)
              .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
                Text("\(results.successful) podcasts imported")
              }

              if results.skipped > 0 {
                HStack {
                  Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.blue)
                  Text("\(results.skipped) already subscribed")
                }
              }

              if results.failed > 0 {
                HStack {
                  Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                  Text("\(results.failed) failed")
                }
              }
            }
            .font(.subheadline)

            if !results.failedPodcasts.isEmpty {
              VStack(alignment: .leading, spacing: 4) {
                Text("Failed URLs:")
                  .font(.caption)
                  .foregroundStyle(.secondary)

                ForEach(results.failedPodcasts.prefix(3), id: \.self) { url in
                  Text(url)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                }

                if results.failedPodcasts.count > 3 {
                  Text("... and \(results.failedPodcasts.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
              }
              .padding()
              .background(Color.gray.opacity(0.1))
              .clipShape(.rect(cornerRadius: 8))
            }

            Button("Done") {
              importManager.dismissImportSheet()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 16)
          }
          .padding()
        } else {
          // Initial/waiting state
          VStack(spacing: 16) {
            ProgressView()
              .scaleEffect(1.5)
            Text("Preparing import...")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle("Import Podcasts")
      #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        if !importManager.isImporting {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
              importManager.dismissImportSheet()
            }
          }
        }
      }
      .interactiveDismissDisabled(importManager.isImporting)
    }
  }
}

// MARK: - Navigation Destinations

extension View {
  /// Registers type-based navigationDestination handlers for the shared route types.
  /// Called on each tab's root view inside its NavigationStack.
  ///
  /// Both NavigationLink(value:) pushes and programmatic NavigationPath.append()
  /// pushes resolve through these same `for:` handlers — no `isPresented:` needed.
  func navigationDestinations() -> some View {
    self
      .navigationDestination(for: EpisodeDetailRoute.self) { route in
        EpisodeDetailView(
          episode: route.episode,
          podcastTitle: route.podcastTitle,
          fallbackImageURL: route.fallbackImageURL,
          podcastLanguage: route.podcastLanguage ?? "en"
        )
      }
      #if os(iOS)
      .navigationDestination(for: EpisodeTranscriptRoute.self) { route in
        EpisodeTranscriptPage(
          episode: route.episode,
          podcastTitle: route.podcastTitle,
          fallbackImageURL: route.fallbackImageURL,
          podcastLanguage: route.podcastLanguage ?? "en"
        )
      }
      .navigationDestination(for: EpisodeAIAnalysisRoute.self) { route in
        EpisodeAIAnalysisPage(
          episode: route.episode,
          podcastTitle: route.podcastTitle,
          fallbackImageURL: route.fallbackImageURL,
          podcastLanguage: route.podcastLanguage ?? "en"
        )
      }
      #endif
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
  }
}

#Preview {
  ContentView()
    .modelContainer(for: PodcastInfoModel.self, inMemory: true)
}
