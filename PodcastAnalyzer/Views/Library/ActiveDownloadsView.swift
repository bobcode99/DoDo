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
        VStack(spacing: 16) {
          Image(systemName: "arrow.down.circle")
            .font(.system(size: 50))
            .foregroundStyle(.secondary)
          Text("No Active Downloads")
            .font(.headline)
          Text("Downloads in progress will appear here")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
