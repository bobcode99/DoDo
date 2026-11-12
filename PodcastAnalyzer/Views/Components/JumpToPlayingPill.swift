//
//  JumpToPlayingPill.swift
//  PodcastAnalyzer
//
//  Small floating icon pill that re-aligns the transcript with audio playback.
//  Shown when the user has paused auto-scroll while the episode is the
//  currently-loaded one, and dismissed during search to avoid clutter.
//
//  It sits in a corner of the transcript, top-trailing by default; the corner
//  is picked in Settings → Appearance and applies to every episode.
//

import SwiftUI

enum JumpToPlayingCorner: String, CaseIterable, Identifiable {
  case topTrailing
  case topLeading
  case bottomTrailing
  case bottomLeading

  static let storageKey = "jumpToPlayingCorner"

  var id: String { rawValue }

  var titleKey: LocalizedStringKey {
    switch self {
    case .topTrailing: "Top Right"
    case .topLeading: "Top Left"
    case .bottomTrailing: "Bottom Right"
    case .bottomLeading: "Bottom Left"
    }
  }

  var alignment: Alignment {
    switch self {
    case .topTrailing: .topTrailing
    case .topLeading: .topLeading
    case .bottomTrailing: .bottomTrailing
    case .bottomLeading: .bottomLeading
    }
  }

  var isTop: Bool { self == .topTrailing || self == .topLeading }
}

struct JumpToPlayingPill: View {
    var isVisible: Bool
    var action: () -> Void

    @AppStorage(JumpToPlayingCorner.storageKey)
    private var cornerRaw = JumpToPlayingCorner.topTrailing.rawValue

    @Environment(\.appAccentColor) private var accent
    @Environment(\.colorScheme) private var colorScheme

    private var corner: JumpToPlayingCorner {
        JumpToPlayingCorner(rawValue: cornerRaw) ?? .topTrailing
    }

    var body: some View {
        Group {
            if isVisible {
                pill.transition(.move(edge: corner.isTop ? .top : .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
        .animation(.snappy(duration: 0.25), value: isVisible)
    }

    private var pill: some View {
        let fill = AccentFill.color(accent, colorScheme)
        return Button(action: action) {
            Image(systemName: "scope")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(fill.contrastingLabel)
                .glassEffect(Glass.regular.tint(fill), in: .capsule)
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                // The pill is drawn small; the tap target stays 44pt.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to playing")
        .padding(12)
    }
}
