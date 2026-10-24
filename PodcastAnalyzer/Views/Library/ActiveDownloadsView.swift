//
//  ActiveDownloadsView.swift
//  PodcastAnalyzer
//
//  Full list of all currently downloading episodes with cancel support.
//

import SwiftUI

struct ActiveDownloadsView: View {
  let viewModel: LibraryViewModel
  private let downloadManager = DownloadManager.shared

  var body: some View {
    Group {
      if viewModel.downloadingEpisodes.isEmpty {
        ContentUnavailableView(
          "No Active Downloads",
          systemImage: "arrow.down.circle",
          description: Text("Downloads in progress will appear here")
        )
      } else {
        List {
          ForEach(viewModel.downloadingEpisodes) { episode in
            ActiveDownloadRow(episode: episode, downloadManager: downloadManager)
              .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
          }
        }
        .listStyle(.plain)
      }
    }
    .navigationTitle("Downloading")
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #endif
  }
}
