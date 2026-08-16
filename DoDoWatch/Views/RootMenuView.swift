//
//  RootMenuView.swift
//  DoDoWatch
//
//  Root of the watch app: a play-source picker over the menu, the same shape
//  Pocket Casts uses (UI/Main Page/SourceInterfaceNavigationView.swift).
//

import SwiftData
import SwiftUI

struct RootMenuView: View {
  @Environment(\.modelContext) private var modelContext
  @State private var sourceManager = SourceManager.shared

  var body: some View {
    NavigationStack {
      List {
        Section {
          Picker("Play on", selection: $sourceManager.selected) {
            ForEach(PlaySource.allCases) { source in
              Label(source.title, systemImage: source.systemImage).tag(source)
            }
          }
          .pickerStyle(.navigationLink)
        }

        Section {
          NavigationLink {
            NowPlayingView()
          } label: {
            Label("Now Playing", systemImage: "play.circle")
          }

          // Both read the shared store, so they are about episodes rather than
          // about which device is playing — no reason to hide them per source.
          NavigationLink {
            UpNextView()
          } label: {
            Label("Up Next", systemImage: "text.line.first.and.arrowtriangle.forward")
          }

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
    }
    .task {
      WatchSessionManager.shared.activate()
      #if DEBUG
      DebugSeed.apply(to: modelContext)
      #endif
    }
  }
}
