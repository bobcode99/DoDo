//
//  RootMenuView.swift
//  DoDoWatch
//
//  One list, the shape of the system Podcasts app on watch: what's playing,
//  then Up Next, then the library. No menu of menus and no "play on" picker —
//  the system Now Playing screen already follows whichever device is playing.
//

import SwiftData
import SwiftUI

struct RootMenuView: View {
  @Environment(\.modelContext) private var modelContext
  @State private var player = WatchAudioPlayer.shared
  @State private var session = WatchSessionManager.shared
  @State private var showPlayer = false
  /// Opened once per launch at most; backing out must stay backed out.
  @State private var didOpenPlayer = false

  private var somethingIsPlaying: Bool {
    player.isPlaying || session.nowPlaying?.isPlaying == true
  }

  /// The watch's own episode wins; otherwise whatever the phone last reported.
  private var nowPlaying: (title: String, subtitle: String, imageURL: String?)? {
    if let episode = player.episode, player.isPlaying || session.nowPlaying?.isPlaying != true {
      return (episode.title, episode.podcastTitle, episode.imageURL)
    }
    if let phone = session.nowPlaying, !phone.episodeTitle.isEmpty {
      return (phone.episodeTitle, phone.podcastTitle, phone.imageURL)
    }
    return nil
  }

  var body: some View {
    NavigationStack {
      List {
        if let nowPlaying {
          Section("Now Playing") {
            NavigationLink {
              PlayerScreen()
            } label: {
              EpisodeRow(title: nowPlaying.title, subtitle: nowPlaying.subtitle, imageURL: nowPlaying.imageURL)
            }
          }
        }

        Section("Up Next") {
          UpNextRows()
        }

        Section("Library") {
          NavigationLink {
            ShowsListView()
          } label: {
            Label("Shows", systemImage: "square.grid.2x2")
          }
          NavigationLink {
            DownloadsView()
          } label: {
            Label("Downloads", systemImage: "arrow.down.circle")
          }
        }
      }
      .navigationTitle("DoDo")
      .navigationDestination(isPresented: $showPlayer) { PlayerScreen() }
    }
    // Raising the wrist mid-episode should land on the controls, not the list.
    // The phone's state arrives a moment after launch, hence onChange too.
    .onAppear(perform: openPlayerIfPlaying)
    .onChange(of: somethingIsPlaying) { openPlayerIfPlaying() }
    .task {
      session.activate()
      #if DEBUG
      DebugSeed.apply(to: modelContext)
      #endif
    }
  }

  private func openPlayerIfPlaying() {
    guard somethingIsPlaying, !didOpenPlayer else { return }
    didOpenPlayer = true
    showPlayer = true
  }
}
