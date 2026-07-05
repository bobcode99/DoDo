//
//  NowPlayingWidget.swift
//  PodcastAnalyzerWidget
//
//  Now Playing widget showing current episode with artwork and playback control.
//  Uses .widgetURL for background navigation and Button(intent:) for play/pause isolation.
//  Uses contentMarginsDisabled() for full-bleed artwork; widgetContentMargins for overlay content.
//

import AppIntents
import SwiftUI
import WidgetKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Image {
  init?(artworkData: Data) {
    #if canImport(UIKit)
    guard let image = UIImage(data: artworkData) else { return nil }
    self.init(uiImage: image)
    #elseif canImport(AppKit)
    guard let image = NSImage(data: artworkData) else { return nil }
    self.init(nsImage: image)
    #else
    return nil
    #endif
  }
}

// MARK: - Widget Entry

struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let playbackData: WidgetPlaybackData?
  /// Artwork image data loaded from shared container at timeline creation time
  let artworkData: Data?

  static var placeholder: NowPlayingEntry {
    NowPlayingEntry(
      date: Date(),
      playbackData: WidgetPlaybackData(
        episodeTitle: "Episode Title",
        podcastTitle: "Podcast Name",
        imageURL: nil,
        audioURL: nil,
        currentTime: 300,
        duration: 1800,
        isPlaying: true,
        lastUpdated: Date()
      ),
      artworkData: nil
    )
  }

  static var empty: NowPlayingEntry {
    NowPlayingEntry(date: Date(), playbackData: nil, artworkData: nil)
  }
}

// MARK: - Configuration Intent (required by AppIntentTimelineProvider)

struct NowPlayingConfiguration: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Now Playing"
  static let description: IntentDescription = "Shows the currently playing podcast episode."
}

// MARK: - Timeline Provider (iOS 17+ async)

struct NowPlayingProvider: AppIntentTimelineProvider {
  typealias Entry = NowPlayingEntry
  typealias Intent = NowPlayingConfiguration

  func placeholder(in context: Context) -> NowPlayingEntry {
    .placeholder
  }

  func snapshot(for configuration: NowPlayingConfiguration, in context: Context) async -> NowPlayingEntry {
    if context.isPreview {
      return .placeholder
    }
    return createEntry()
  }

  func timeline(for configuration: NowPlayingConfiguration, in context: Context) async -> Timeline<NowPlayingEntry> {
    let entry = createEntry()

    // Paused / empty: nothing moves on its own — the app pushes
    // WidgetCenter.reloadTimelines() on every play/pause/episode change, so a
    // slow fallback refresh is enough (frequent .after() just burns the
    // ~40-70/day WidgetKit reload budget and gets throttled anyway).
    guard let data = entry.playbackData, data.isPlaying else {
      return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60)))
    }

    // Playing: pre-render one entry per minute with an extrapolated playhead so
    // the progress bar advances between reloads at zero budget cost — WidgetKit
    // swaps entries from a single timeline for free.
    // ponytail: extrapolates at 1× — playbackRate isn't in the shared payload;
    // add it there if 1.5×/2× listeners notice the bar lagging.
    let now = Date()
    let remainingMinutes = max(Int((data.duration - data.currentTime) / 60), 0)
    let horizon = min(remainingMinutes + 1, 30)
    let entries = (0...horizon).map { minute -> NowPlayingEntry in
      let offset = TimeInterval(minute * 60)
      let extrapolated = WidgetPlaybackData(
        episodeTitle: data.episodeTitle,
        podcastTitle: data.podcastTitle,
        imageURL: data.imageURL,
        audioURL: data.audioURL,
        currentTime: min(data.currentTime + offset, data.duration),
        duration: data.duration,
        isPlaying: true,
        lastUpdated: data.lastUpdated
      )
      return NowPlayingEntry(
        date: now.addingTimeInterval(offset),
        playbackData: extrapolated,
        artworkData: entry.artworkData
      )
    }
    return Timeline(entries: entries, policy: .after(now.addingTimeInterval(TimeInterval(horizon * 60))))
  }

  private func createEntry() -> NowPlayingEntry {
    guard let data = WidgetDataManager.readPlaybackData(),
          !WidgetDataManager.isDataStale(data) else {
      return .empty
    }
    let artworkData = WidgetDataManager.readArtworkData()
    return NowPlayingEntry(date: Date(), playbackData: data, artworkData: artworkData)
  }
}

// MARK: - Entry View Router

struct NowPlayingWidgetEntryView: View {
  var entry: NowPlayingEntry
  @Environment(\.widgetFamily) var family

  var body: some View {
    switch family {
    case .systemSmall:
      SmallWidgetView(entry: entry)
    case .systemMedium:
      MediumWidgetView(entry: entry)
    default:
      SmallWidgetView(entry: entry)
    }
  }
}

// MARK: - Small Widget View
// Full-bleed artwork + gradient, overlay content uses widgetContentMargins for safe placement

struct SmallWidgetView: View {
  let entry: NowPlayingEntry
  @Environment(\.widgetContentMargins) private var margins

  var body: some View {
    if let data = entry.playbackData {
      ZStack {
        // Layer 1: full-bleed artwork (no padding — contentMarginsDisabled on config)
        artworkBackground

        // Layer 2: gradient scrim over bottom half
        LinearGradient(
          colors: [.clear, .black.opacity(0.72)],
          startPoint: .center,
          endPoint: .bottom
        )

        // Layer 3: overlay content using widgetContentMargins
        VStack(spacing: 0) {
          // Play/pause button — top-right
          HStack {
            Spacer()
            if data.isPlaying {
              Button(intent: TogglePlaybackIntent()) {
                ZStack {
                  Circle()
                    .fill(.black.opacity(0.38))
                    .frame(width: 34, height: 34)
                  Image(systemName: "pause.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Pause")
            } else {
              Button(intent: ResumePlaybackIntent()) {
                ZStack {
                  Circle()
                    .fill(.black.opacity(0.38))
                    .frame(width: 34, height: 34)
                  Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: 1)
                }
                .frame(width: 44, height: 44)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Play")
            }
          }

          Spacer()

          // Episode info — bottom-left
          HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
              Text(data.episodeTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)

              Text(data.podcastTitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
            Spacer()
          }
        }
        .padding(margins)
      }
      .widgetURL(data.episodeDetailURL)
    } else {
      EmptyWidgetView()
    }
  }

  @ViewBuilder
  private var artworkBackground: some View {
    if let artworkData = entry.artworkData, let image = Image(artworkData: artworkData) {
      image
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else {
      LinearGradient(
        colors: [Color(white: 0.18), Color(white: 0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .overlay {
        Image(systemName: "headphones")
          .font(.system(size: 32))
          .foregroundStyle(.white.opacity(0.25))
      }
    }
  }
}

// MARK: - Medium Widget View
// Left: square artwork panel sized to widget height. Right: info with widgetContentMargins.
// GeometryReader reads the full widget height so the artwork is never cropped.

struct MediumWidgetView: View {
  let entry: NowPlayingEntry
  @Environment(\.widgetContentMargins) private var margins

  var body: some View {
    if let data = entry.playbackData {
      GeometryReader { geo in
        HStack(spacing: 0) {
          // Left: square artwork — width equals widget height so the 1:1 artwork
          // fills exactly without cropping (avoids the .fill + taller-frame clip).
          artworkPanel
            .frame(width: geo.size.height, height: geo.size.height)
            .clipped()

          // Right: episode info, padded using widgetContentMargins
          VStack(alignment: .leading, spacing: 0) {
            Text(data.episodeTitle)
              .font(.subheadline)
              .fontWeight(.semibold)
              .lineLimit(2)
              .foregroundStyle(.primary)

            Text(data.podcastTitle)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .padding(.top, 4)

            Spacer(minLength: 8)

            // Progress bar
            GeometryReader { barGeo in
              ZStack(alignment: .leading) {
                Capsule()
                  .fill(Color.primary.opacity(0.12))
                  .frame(height: 3)
                Capsule()
                  .fill(Color.blue)
                  .frame(width: max(barGeo.size.width * data.progress, 0), height: 3)
              }
            }
            .frame(height: 3)
            .padding(.bottom, 6)

            // Play/pause button — trailing
            HStack {
              Spacer()
              if data.isPlaying {
                Button(intent: TogglePlaybackIntent()) {
                  Image(systemName: "pause.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pause")
              } else {
                Button(intent: ResumePlaybackIntent()) {
                  Image(systemName: "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play")
              }
            }
          }
          .padding(.leading, 14)
          .padding(.trailing, margins.trailing)
          .padding(.top, margins.top)
          .padding(.bottom, margins.bottom)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
      }
      .widgetURL(data.episodeDetailURL)
    } else {
      EmptyWidgetView()
    }
  }

  @ViewBuilder
  private var artworkPanel: some View {
    if let artworkData = entry.artworkData, let image = Image(artworkData: artworkData) {
      image
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else {
      LinearGradient(
        colors: [Color(white: 0.18), Color(white: 0.10)],
        startPoint: .top,
        endPoint: .bottom
      )
      .overlay {
        Image(systemName: "headphones")
          .font(.system(size: 24))
          .foregroundStyle(.white.opacity(0.25))
      }
    }
  }
}

// MARK: - Empty Widget View

struct EmptyWidgetView: View {
  @Environment(\.widgetContentMargins) private var margins

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "headphones")
        .font(.title)
        .foregroundStyle(.blue.opacity(0.6))
      Text("No Episode Playing")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("Open app to start listening")
        .font(.caption2)
        .foregroundStyle(.secondary.opacity(0.8))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .widgetURL(URL(string: "podcastanalyzer://library"))
  }
}

// MARK: - Widget Configuration

struct NowPlayingWidget: Widget {
  let kind: String = "NowPlayingWidget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(kind: kind, intent: NowPlayingConfiguration.self, provider: NowPlayingProvider()) { entry in
      NowPlayingWidgetEntryView(entry: entry)
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName("Now Playing")
    .description("Shows the currently playing podcast episode with progress.")
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
  NowPlayingWidget()
} timeline: {
  NowPlayingEntry.placeholder
  NowPlayingEntry.empty
}

#Preview("Medium", as: .systemMedium) {
  NowPlayingWidget()
} timeline: {
  NowPlayingEntry.placeholder
  NowPlayingEntry.empty
}
