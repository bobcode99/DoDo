//
//  MacLibraryPodcastRow.swift
//  PodcastAnalyzer
//
//  macOS Library — compact podcast row (used by MacSearchView library results)
//

#if os(macOS)
import SwiftUI

struct MacLibraryPodcastRow: View {
  let podcastModel: PodcastInfoModel

  var body: some View {
    HStack(spacing: 12) {
      CachedArtworkImage(urlString: podcastModel.imageURL, size: 56, cornerRadius: 8)

      VStack(alignment: .leading, spacing: 2) {
        Text(podcastModel.title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)

        Text("Show · \(podcastModel.episodeCount) episodes")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Image(systemName: "checkmark")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.primary)
    }
    .padding(.vertical, 4)
  }
}
#endif
