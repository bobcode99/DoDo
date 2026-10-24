//
//  AnalysisResultCardView.swift
//  PodcastAnalyzer
//
//  Renders a completed CloudAnalysisResult: structured sections, metadata,
//  and share/regenerate/copy-prompt actions.
//

import SwiftUI

struct AnalysisResultCardView: View {
  let result: CloudAnalysisResult
  let viewModel: EpisodeDetailViewModel
  let uiState: AIAnalysisUIState

  @Environment(\.openURL) private var openURL

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // Show warning if JSON parsing failed
      if let warning = result.jsonParseWarning {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text("Response Format Warning")
              .font(.caption)
              .fontWeight(.semibold)
              .foregroundStyle(.orange)
            Text(warning)
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
      }

      // Structured content based on type
      switch result.type {
      case .analysis:
        fullAnalysisResultView(result)
      }

      Divider()

      // Metadata
      HStack {
        ProviderIconLabel(provider: result.provider, iconSize: 13)
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()

        Text(result.model)
          .font(.caption)
          .foregroundStyle(.secondary)

        Text(Formatters.formatDate(result.timestamp, time: .shortened))
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // Share & Regenerate buttons
      HStack {
        if let parsed = result.parsedAnalysis {
          Button(action: {
            let text = parsed.formatAsShareableText(
              episodeTitle: viewModel.episode.title,
              podcastTitle: viewModel.podcastTitle
            )
            PlatformShareSheet.share(items: [text])
          }) {
            Label("Share", systemImage: "square.and.arrow.up")
              .font(.caption)
          }
          .buttonStyle(.bordered)
        }

        Button(action: {
          uiState.isRegenerating = true
        }) {
          Label("Regenerate", systemImage: "arrow.clockwise")
            .font(.caption)
        }
        .buttonStyle(.bordered)

        Spacer(minLength: 0)

        if viewModel.hasTranscript {
          Button {
            uiState.showPromptPreview = true
          } label: {
            Label("Copy Prompt", systemImage: "doc.on.doc")
              .font(.caption)
          }
          .buttonStyle(.bordered)
        }
      }
    }
    .padding()
    .background(Color.platformSystemGray6)
    .clipShape(.rect(cornerRadius: 12))
  }

  // MARK: - Structured Result Views

  @ViewBuilder
  private func entitySection(title: LocalizedStringKey, icon: String, items: [String], color: Color)
    -> some View
  {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Label(title, systemImage: icon)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(color)

        FlowLayout(spacing: 8) {
          ForEach(items, id: \.self) { item in
            Text(item)
              .font(.caption)
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(color.opacity(0.1))
              .foregroundStyle(color)
              .clipShape(.rect(cornerRadius: 16))
          }
        }
      }
    }
  }

  // MARK: - Analysis Result View

  @ViewBuilder
  private func fullAnalysisResultView(_ result: CloudAnalysisResult) -> some View {
    if let parsed = result.parsedAnalysis {
      VStack(alignment: .leading, spacing: 20) {
        // Overview
        VStack(alignment: .leading, spacing: 8) {
          Label("Overview", systemImage: "doc.text")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.blue)

          timestampAwareText(parsed.overview)
        }

        bulletSection(
          "Key Takeaways", systemImage: "lightbulb.fill", tint: .orange,
          items: parsed.keyTakeaways, bullet: "checkmark.circle.fill", bulletTint: .green
        )

        if !parsed.targetAudience.isEmpty || !parsed.engagementLevel.isEmpty {
          audienceRow(parsed)
        }

        if !parsed.mainTopics.isEmpty {
          mainTopicsSection(parsed.mainTopics)
        }

        VStack(alignment: .leading, spacing: 16) {
          entitySection(title: "People", icon: "person.fill", items: parsed.people, color: .blue)
          entitySection(title: "Organizations", icon: "building.2.fill", items: parsed.organizations, color: .purple)
          entitySection(title: "Products", icon: "shippingbox.fill", items: parsed.products, color: .orange)
          entitySection(title: "Locations", icon: "mappin.circle.fill", items: parsed.locations, color: .green)
          entitySection(title: "Resources", icon: "book.fill", items: parsed.resources, color: .red)
        }

        bulletSection(
          "Highlights", systemImage: "star.fill", tint: .yellow,
          items: parsed.highlights, bullet: "star.fill", bulletTint: .yellow
        )
        bulletSection(
          "Key Insights", systemImage: "lightbulb.fill", tint: .orange,
          items: parsed.keyInsights, bullet: "lightbulb.fill", bulletTint: .orange
        )

        if !parsed.notableQuotes.isEmpty {
          notableQuotesSection(parsed.notableQuotes)
        }

        bulletSection(
          "Action Items", systemImage: "checkmark.circle.fill", tint: .teal,
          items: parsed.actionItems, bullet: "arrow.right.circle.fill", bulletTint: .teal
        )
        bulletSection(
          "Controversial Points", systemImage: "exclamationmark.triangle.fill", tint: .orange,
          items: parsed.controversialPoints ?? [], bullet: "exclamationmark.triangle.fill", bulletTint: .orange
        )
        bulletSection(
          "Entertaining Moments", systemImage: "face.smiling.fill", tint: .pink,
          items: parsed.entertainingMoments ?? [], bullet: "face.smiling.fill", bulletTint: .pink
        )

        if let qaItems = parsed.qaHighlights, !qaItems.isEmpty {
          qaHighlightsSection(qaItems)
        }

    VStack(alignment: .leading, spacing: 8) {
      Label("Conclusion", systemImage: "checkmark.seal.fill")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.indigo)

      VStack(alignment: .leading, spacing: 4) {
        timestampAwareText(parsed.conclusion)
      }
      .padding()
      .background(Color.indigo.opacity(0.1))
      .clipShape(.rect(cornerRadius: 8))
    }
      }
    } else {
      selectableText(result.content)
    }
  }

  /// Heading plus one icon-led row per item; renders nothing when `items` is empty.
  @ViewBuilder
  private func bulletSection(
    _ title: LocalizedStringKey, systemImage: String, tint: Color,
    items: [String], bullet: String, bulletTint: Color
  ) -> some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Label(title, systemImage: systemImage)
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundStyle(tint)

        ForEach(items.enumerated(), id: \.offset) { _, item in
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: bullet)
              .foregroundStyle(bulletTint)
              .font(.caption)
              .accessibilityHidden(true)
            selectableText(item)
          }
        }
      }
    }
  }

  private func audienceRow(_ parsed: ParsedEpisodeAnalysisResponse) -> some View {
    HStack(spacing: 16) {
      if !parsed.targetAudience.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Target Audience")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(parsed.targetAudience)
            .font(.caption)
            .fontWeight(.medium)
        }
      }

      if !parsed.engagementLevel.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Engagement")
            .font(.caption)
            .foregroundStyle(.secondary)
          HStack(spacing: 4) {
            engagementIcon(parsed.engagementLevel)
            Text(parsed.engagementLevel.capitalized)
              .font(.caption)
              .fontWeight(.medium)
          }
        }
      }
    }
  }

  private func mainTopicsSection(_ topics: [ParsedEpisodeAnalysisResponse.TopicDetail]) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Main Topics", systemImage: "list.bullet.rectangle")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.purple)

      ForEach(topics.enumerated(), id: \.offset) { _, topic in
        VStack(alignment: .leading, spacing: 6) {
          Text(topic.topic)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.primary)

          selectableText(topic.summary)
            .font(.caption)
            .foregroundStyle(.secondary)

          ForEach(topic.keyPoints, id: \.self) { point in
            HStack(alignment: .top, spacing: 8) {
              Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(.purple)
                .padding(.top, 6)
                .accessibilityHidden(true)
              selectableText(point)
                .font(.caption)
            }
          }
        }
        .padding()
        .background(Color.purple.opacity(0.05))
        .clipShape(.rect(cornerRadius: 8))
      }
    }
  }

  private func notableQuotesSection(_ quotes: [TimestampedQuote]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Notable Quotes", systemImage: "quote.opening")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.green)

      ForEach(quotes.enumerated(), id: \.offset) { _, quote in
        VStack(alignment: .leading, spacing: 6) {
          selectableText("\"\(quote.text)\"")
            .font(.subheadline)
            .italic()

          if let seconds = quote.timeInSeconds {
            timestampBadge(quote.timestamp!, seconds: seconds)
          }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.green.opacity(0.1))
        )
        .overlay(
          Rectangle()
            .fill(Color.green)
            .frame(width: 4),
          alignment: .leading
        )
      }
    }
  }

  private func qaHighlightsSection(_ qaItems: [QAHighlight]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Q&A Highlights", systemImage: "bubble.left.and.bubble.right.fill")
        .font(.subheadline)
        .fontWeight(.semibold)
        .foregroundStyle(.cyan)

      ForEach(qaItems.enumerated(), id: \.offset) { _, item in
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
              .foregroundStyle(.cyan)
              .font(.caption)
              .accessibilityHidden(true)
            selectableText(item.question)
              .fontWeight(.medium)
          }
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
              .foregroundStyle(.secondary)
              .font(.caption)
              .padding(.leading, 2)
              .accessibilityHidden(true)
            selectableText(item.answer)
              .foregroundStyle(.secondary)
          }
        }
        .padding()
        .background(Color.cyan.opacity(0.05))
        .clipShape(.rect(cornerRadius: 8))
      }
    }
  }

  private func engagementIcon(_ level: String) -> some View {
    let iconName: String
    let color: Color
    switch level.lowercased() {
    case "high":
      iconName = "flame.fill"
      color = .red
    case "medium":
      iconName = "circle.lefthalf.filled"
      color = .orange
    default:
      iconName = "circle"
      color = .gray
    }
    return Image(systemName: iconName)
      .foregroundStyle(color)
      .font(.caption)
      .accessibilityHidden(true)
  }

  // MARK: - Selectable Text with Context Menu

  /// Text view with selection enabled and context menu for copy, translate, search
  private func selectableText(_ content: String) -> some View {
    Text(content)
      .font(.body)
      .textSelection(.enabled)
      .contextMenu {
        Button {
          PlatformClipboard.string = content
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
        }

        Button {
          // Open in Safari for web search
          if let query = content.prefix(100).addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://www.google.com/search?q=\(query)")
          {
            openURL(url)
          }
        } label: {
          Label("Search Web", systemImage: "magnifyingglass")
        }

        ShareLink(item: content) {
          Label("Share", systemImage: "square.and.arrow.up")
        }
      }
  }

  // MARK: - Timestamp Badge

  /// Tappable timestamp pill with Play and Share actions
  private func timestampBadge(_ timestamp: String, seconds: TimeInterval) -> some View {
    TimestampLink(
      text: timestamp,
      seconds: seconds,
      onPlay: { viewModel.seekToTime(seconds) },
      onShare: { viewModel.shareTimestampedLink(seconds: seconds) }
    )
  }

  // MARK: - Timestamp-Aware Text

  /// Text view that detects inline timestamps and shows tappable chips below
  @ViewBuilder
  private func timestampAwareText(_ content: String) -> some View {
    let timestamps = TimestampUtils.findTimestamps(in: content)
    selectableText(content)
    if !timestamps.isEmpty {
      FlowLayout(spacing: 6) {
        ForEach(timestamps.indices, id: \.self) { i in
          timestampBadge(timestamps[i].text, seconds: timestamps[i].seconds)
        }
      }
    }
  }
}
