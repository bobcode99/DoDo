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
      CachedArtworkImage(urlString: podcastModel.podcastInfo.imageURL, size: 56, cornerRadius: 8)

      VStack(alignment: .leading, spacing: 2) {
        Text(podcastModel.podcastInfo.title)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)

        Text("Show · \(podcastModel.podcastInfo.episodes.count) episodes")
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
