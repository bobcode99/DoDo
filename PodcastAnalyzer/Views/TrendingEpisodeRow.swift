//
//  TrendingEpisodeRow.swift
//  PodcastAnalyzer
//
//  Created by JunNianLo on 2026/5/16.
//


import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct TrendingEpisodeRow: View {
  let episode: ApplePodcastService.TrendingEpisode
  let rank: Int

  private static let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  private static let isoFormatterNoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()

  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
  }()

  private var formattedDuration: String {
    guard let millis = episode.episode.trackTimeMillis else { return "" }
    let totalSeconds = millis / 1000
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    if hours > 0 {
      return "\(hours)h \(minutes)m"
    }
    return "\(minutes) min"
  }

  private var relativeDate: String {
    guard let dateStr = episode.episode.releaseDate else { return "" }
    guard let date = Self.isoFormatter.date(from: dateStr)
            ?? Self.isoFormatterNoFrac.date(from: dateStr) else { return "" }
    return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
  }

  private var metadataText: String {
    let parts = [relativeDate, formattedDuration].filter { !$0.isEmpty }
    return parts.joined(separator: " · ")
  }

  var body: some View {
    HStack(spacing: 10) {
      Text("\(rank)")
        .font(.footnote)
        .fontWeight(.bold)
        .foregroundStyle(.secondary)
        .frame(width: 18, alignment: .trailing)
        .monospacedDigit()

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