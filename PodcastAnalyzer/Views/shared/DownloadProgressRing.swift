//
//  DownloadProgressRing.swift
//  PodcastAnalyzer
//
//  Single Apple-style circular download indicator used everywhere a download
//  progress is shown (episode list rows, episode detail, transcript sheet,
//  library download rows, status icon strips) so the app has one consistent
//  look: a ring that fills up — no percentage numbers.
//

import SwiftUI

/// Static ring — caller supplies the progress value.
struct DownloadProgressRing: View {
  let progress: Double
  var size: CGFloat = 16
  var lineWidth: CGFloat = 2
  var color: Color = .blue
  /// Optional SF Symbol rendered inside the ring (e.g. "arrow.down",
  /// "stop.fill" for a tappable cancel ring, "xmark").
  var symbol: String?

  var body: some View {
    ZStack {
      Circle()
        .stroke(color.opacity(0.25), lineWidth: lineWidth)
      Circle()
        // Small floor so a just-started download reads as "in progress"
        // instead of an empty circle.
        .trim(from: 0, to: max(min(progress, 1), 0.03))
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .animation(.linear(duration: 0.3), value: progress)
      if let symbol {
        Image(systemName: symbol)
          .font(.system(size: size * 0.4, weight: .bold))
          .foregroundStyle(color)
      }
    }
    .frame(width: size, height: size)
  }
}

/// Self-updating ring for an in-flight episode download.
///
/// Live progress lives in `DownloadManager.inFlightProgress`, which is
/// deliberately `@ObservationIgnored` so progress ticks don't invalidate whole
/// lists. That also means views that read it via computed properties freeze at
/// the last state transition. This view sidesteps the problem: a `TimelineView`
/// re-reads the value every half second while visible, so the ring always shows
/// current progress with zero external plumbing (no per-ViewModel timers, no
/// snapshots). Parents show/hide it based on the observable `downloadStates`
/// transition, which bounds the periodic timeline to active downloads only.
struct LiveDownloadProgressRing: View {
  let episodeKey: String
  var size: CGFloat = 16
  var lineWidth: CGFloat = 2
  var color: Color = .blue
  var symbol: String?

  init(
    episodeKey: String,
    size: CGFloat = 16,
    lineWidth: CGFloat = 2,
    color: Color = .blue,
    symbol: String? = nil
  ) {
    self.episodeKey = episodeKey
    self.size = size
    self.lineWidth = lineWidth
    self.color = color
    self.symbol = symbol
  }

  init(
    episodeTitle: String,
    podcastTitle: String,
    size: CGFloat = 16,
    lineWidth: CGFloat = 2,
    color: Color = .blue,
    symbol: String? = nil
  ) {
    self.init(
      episodeKey: EpisodeKeyUtils.makeKey(podcastTitle: podcastTitle, episodeTitle: episodeTitle),
      size: size,
      lineWidth: lineWidth,
      color: color,
      symbol: symbol
    )
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
      DownloadProgressRing(
        progress: DownloadManager.shared.inFlightProgress[episodeKey] ?? 0,
        size: size,
        lineWidth: lineWidth,
        color: color,
        symbol: symbol
      )
    }
  }
}
