//
//  NowPlayingComplication.swift
//  DoDoWatchWidget
//
//  WidgetKit accessory families, not ClockKit. Pocket Casts still ships a
//  CLKComplicationDataSource whose every template is a static asset plus
//  "Tap to open" (Complication/ComplicationController.swift:46-120) — it
//  carries no data at all. This one shows what is actually playing.
//

import SwiftUI
import WidgetKit

struct NowPlayingEntry: TimelineEntry {
  let date: Date
  let state: WatchComplicationState
}

struct NowPlayingProvider: TimelineProvider {
  func placeholder(in context: Context) -> NowPlayingEntry {
    NowPlayingEntry(
      date: .now,
      state: WatchComplicationState(
        episodeTitle: "Episode", podcastTitle: "Podcast", progress: 0.4, isPlaying: true)
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
    completion(NowPlayingEntry(date: .now, state: WatchComplicationStore.read()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
    // A single entry with `.never`: the app reloads this timeline when playback
    // actually changes, so there is nothing useful to predict — and complication
    // refreshes are a scarce budget on watchOS.
    let entry = NowPlayingEntry(date: .now, state: WatchComplicationStore.read())
    completion(Timeline(entries: [entry], policy: .never))
  }
}

struct NowPlayingComplicationView: View {
  @Environment(\.widgetFamily) private var family
  let entry: NowPlayingEntry

  var body: some View {
    switch family {
    case .accessoryCircular:
      ZStack {
        ProgressView(value: entry.state.progress)
          .progressViewStyle(.circular)
        Image(systemName: icon)
          .font(.system(size: 14))
      }
    case .accessoryInline:
      Label(inlineText, systemImage: icon)
    case .accessoryCorner:
      Image(systemName: icon)
        .font(.title3)
        .widgetLabel {
          ProgressView(value: entry.state.progress)
        }
    default:
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.state.hasEpisode ? entry.state.podcastTitle : "DoDo")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Text(entry.state.hasEpisode ? entry.state.episodeTitle : "Nothing playing")
          .font(.caption)
          .lineLimit(2)
        if entry.state.hasEpisode {
          ProgressView(value: entry.state.progress)
        }
      }
    }
  }

  private var icon: String {
    guard entry.state.hasEpisode else { return "headphones" }
    return entry.state.isPlaying ? "play.fill" : "pause.fill"
  }

  private var inlineText: String {
    entry.state.hasEpisode ? entry.state.episodeTitle : "Nothing playing"
  }
}

struct NowPlayingComplication: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WatchComplicationStore.widgetKind, provider: NowPlayingProvider()) {
      entry in
      NowPlayingComplicationView(entry: entry)
        .containerBackground(.clear, for: .widget)
    }
    .configurationDisplayName("Now Playing")
    .description("What DoDo is playing.")
    .supportedFamilies([
      .accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner,
    ])
  }
}

@main
struct DoDoWatchWidgetBundle: WidgetBundle {
  var body: some Widget {
    NowPlayingComplication()
  }
}
