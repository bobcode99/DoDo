//
//  ActiveDownloadsSectionCard.swift
//  PodcastAnalyzer
//
//  Compact card shown at the top of DownloadedPodcastsGridView when
//  downloads are in progress. Tapping navigates to ActiveDownloadsView.
//

import SwiftUI

struct ActiveDownloadsSectionCard: View {
  let viewModel: LibraryViewModel

  var body: some View {
    NavigationLink(value: LibrarySubpageRoute.downloadingEpisodes) {
      HStack(spacing: 12) {
        ZStack {
          Circle()
            .fill(Color.blue.opacity(0.12))
            .frame(width: 44, height: 44)
          ProgressView()
            .scaleEffect(0.7)
            .tint(.blue)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text("Downloading")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
          Text("^[\(viewModel.downloadingEpisodes.count) episode](inflect: true)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }
    .buttonStyle(.plain)
  }
}
