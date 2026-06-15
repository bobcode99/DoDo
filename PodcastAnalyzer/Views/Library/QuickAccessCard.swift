//
//  QuickAccessCard.swift
//  PodcastAnalyzer
//
//  Quick access card and podcast grid cell for the Library tab.
//

import SwiftUI

// MARK: - Quick Access Card

struct QuickAccessCard: View {
  let icon: String
  let iconColor: Color
  let title: LocalizedStringKey
  let count: Int
  var isLoading: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: icon)
          .font(.system(size: 20))
          .foregroundStyle(iconColor)

        Spacer()

        if isLoading {
          ProgressView()
            .scaleEffect(0.6)
        } else {
          Image(systemName: "chevron.right")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)

        Text("\(count) episodes")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, minHeight: 90)
    .glassEffect(Glass.regular, in: .rect(cornerRadius: 12))
  }
}

// MARK: - Podcast Grid Cell

/// Value-type snapshot passed to PodcastGridCell to prevent @Observable observation
/// storms. LibraryView converts [PodcastInfoModel] → [PodcastGridItem] once in
/// updateSortedPodcasts(), so SwiftUI only tracks the cheap value array, not the
/// live model's episode array.
struct PodcastGridItem: Identifiable, Equatable {
  let id: UUID
  let title: String
  let imageURL: String
  let episodeCount: Int
  let latestEpisodeDate: Date?

  init(from model: PodcastInfoModel) {
    self.id = model.id
    // Fast path: read the denormalized mirrors so the grid never decodes the
    // podcastInfo episode blob (the cold-load hang). Rows persisted before
    // these columns existed fall back to a one-time decode; LibraryViewModel
    // .loadAllPodcasts backfills them so subsequent launches take the fast path.
    if model.episodeCount > 0 || !model.imageURL.isEmpty {
      self.title = model.title
      self.imageURL = model.imageURL
      self.episodeCount = model.episodeCount
      self.latestEpisodeDate = model.latestEpisodeDate
    } else {
      let info = model.podcastInfo
      self.title = info.title
      self.imageURL = info.imageURL
      self.episodeCount = info.episodes.count
      self.latestEpisodeDate = info.episodes.lazy.compactMap(\.pubDate).max()
    }
  }
}

struct PodcastGridCell: View {
  let item: PodcastGridItem

  private var latestEpisodeDate: String? {
    guard let date = item.latestEpisodeDate else { return nil }
    return Formatters.formatRelativeDate(date)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      CachedAsyncImage(url: URL(string: item.imageURL)) { image in
        image.resizable().aspectRatio(contentMode: .fill)
      } placeholder: {
        Color.gray.opacity(0.2)
          .overlay(ProgressView().scaleEffect(0.5))
      }
      .aspectRatio(1, contentMode: .fit)
      .clipShape(.rect(cornerRadius: 10))
      .clipped()

      Text(item.title)
        .font(.caption)
        .fontWeight(.medium)
        .lineLimit(2)
        .foregroundStyle(.primary)

      if let dateStr = latestEpisodeDate {
        Text(dateStr)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
  }
}
