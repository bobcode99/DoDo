//
//  RootMenuView.swift
//  DoDoWatch
//
//  Root of the watch app: the menu Pocket Casts puts behind its source picker,
//  minus the picker until there is a phone source to pick.
//

import SwiftData
import SwiftUI

struct RootMenuView: View {
  @Environment(\.modelContext) private var modelContext

  var body: some View {
    NavigationStack {
      List {
        NavigationLink {
          ShowsListView()
        } label: {
          Label("Shows", systemImage: "square.grid.2x2")
        }
      }
      .navigationTitle("DoDo")
    }
    .task {
      #if DEBUG
      DebugSeed.apply(to: modelContext)
      #endif
    }
  }
}
