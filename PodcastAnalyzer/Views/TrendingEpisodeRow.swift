//
//  TrendingEpisodeRow.swift
//  PodcastAnalyzer
//
//  Created by JunNianLo on 2026/5/16.
//

import SwiftData
import SwiftUI

struct TrendingEpisodeRow: View {
  let episode: ApplePodcastService.TrendingEpisode
  /// Chart position; nil for search results, which have no ranking to show.
  let rank: Int?

  @ScaledMetric(relativeTo: .footnote) private var rankWidth: CGFloat = 18

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static let isoFormatterNoFrac: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private var formattedDuration: String {
    guard let millis = episode.episode.trackTimeMillis else { return "" }
    return Duration.milliseconds(millis).formatted(
      .units(allowed: [.hours, .minutes], width: .abbreviated).locale(Formatters.appLocale)
    )
  }

  private var relativeDate: String {
    guard let dateStr = episode.episode.releaseDate else { return "" }
    guard let date = Self.isoFormatter.date(from: dateStr)
            ?? Self.isoFormatterNoFrac.date(from: dateStr) else { return "" }
    // A bare RelativeDateTimeFormatter follows the *device* language, so this
    // stayed Chinese after switching the app to English.
    return Formatters.formatRelativeDate(date, locale: Formatters.appLocale)
  }

  private var metadataText: String {
    let parts = [relativeDate, formattedDuration].filter { !$0.isEmpty }
    return parts.joined(separator: " · ")
  }

  var body: some View {
    HStack(spacing: 10) {
      if let rank {
        Text("\(rank)")
          .font(.footnote)
          .bold()
          .foregroundStyle(.secondary)
          .frame(width: rankWidth, alignment: .trailing)
          .monospacedDigit()
      }

      CachedArtworkImage(urlString: episode.podcastArtworkUrl, size: 40, cornerRadius: 6)

      VStack(alignment: .leading, spacing: 1) {
        Text(episode.episode.trackName)
          .font(.subheadline)
          .fontWeight(.medium)
          .lineLimit(1)
          .truncationMode(.tail)
          .foregroundStyle(.primary)

        if !metadataText.isEmpty {
          Text(metadataText)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
  }
}
