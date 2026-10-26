//
//  AnalysisRowCard.swift
//  PodcastAnalyzer
//
//  Card for one AnalysisView row: artwork, titles, overview snippet, and
//  transcript / analysis / Q&A badges.
//

import SwiftUI

struct AnalysisRowCard: View {
  let entry: AnalysisEntry
  let artworkURL: String?

  private var overviewSnippet: String? {
    entry.analysis?.parsedAnalysis?.overview
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nonEmptyOrNil
  }

  private var qaCount: Int {
    entry.analysis?.qaHistory.count ?? 0
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      artwork
      VStack(alignment: .leading, spacing: 6) {
        Text(entry.podcastTitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Text(entry.episodeTitle)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)
          .lineLimit(2)
        if let snippet = overviewSnippet {
          Text(snippet)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(3)
        }
        // Episodes with every badge overflow one line — drop the badge titles.
        ViewThatFits(in: .horizontal) {
          metadata(badgeStyle: .titleAndIcon)
          metadata(badgeStyle: .iconOnly)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(12)
    .background(Color.platformSystemGray6, in: .rect(cornerRadius: 14))
  }

  private func metadata<S: LabelStyle>(badgeStyle: S) -> some View {
    HStack(spacing: 10) {
      Label(Formatters.formatDate(entry.updatedAt),
            systemImage: "clock")
      Group {
        if entry.transcriptDate != nil {
          Label("Transcript", systemImage: "text.quote")
        }
        if entry.analysis?.hasAnalysis == true {
          Label("Analysis", systemImage: Constants.analysisIconName)
        }
      }
      .labelStyle(badgeStyle)
      if qaCount > 0 {
        Label("\(qaCount) Q&A", systemImage: "bubble.left.and.bubble.right")
      }
    }
  }

  @ViewBuilder
  private var artwork: some View {
    let urlString = artworkURL ?? ""
    let url = URL(string: urlString)
    CachedAsyncImage(url: url) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      ZStack {
        Color.platformSystemGray5
        Image(systemName: Constants.analysisIconName)
          .foregroundStyle(.secondary)
      }
    }
    .frame(width: 64, height: 64)
    .clipShape(.rect(cornerRadius: 8))
    .accessibilityHidden(true)
  }
}

// MARK: - Small string helper

private extension String {
  var nonEmptyOrNil: String? { isEmpty ? nil : self }
}
