//
//  AirPlayButton.swift
//  PodcastAnalyzer
//
//  Created by Bob on 2026/1/2.
//

import AVKit
import SwiftUI

#if os(iOS)
import UIKit

struct AirPlayButton: UIViewRepresentable {
  /// nil = System Default, i.e. the shipped `AccentColor` asset. Read from the
  /// environment rather than hardcoding systemBlue so an active route picks up
  /// the accent the user chose in Settings, like every other control does.
  @Environment(\.appAccentColor) private var appAccentColor

  private var activeTint: UIColor {
    if let appAccentColor { return UIColor(appAccentColor) }
    return UIColor(named: "AccentColor") ?? .tintColor
  }

  func makeUIView(context: Context) -> AVRoutePickerView {
    let picker = AVRoutePickerView()
    picker.backgroundColor = .clear
    picker.tintColor = .secondaryLabel
    picker.activeTintColor = activeTint
    return picker
  }

  /// Re-applied on update: the accent can change while the player is open.
  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
    uiView.activeTintColor = activeTint
  }
}

#elseif os(macOS)
import AppKit

struct AirPlayButton: NSViewRepresentable {
  func makeNSView(context: Context) -> AVRoutePickerView {
    let picker = AVRoutePickerView()
    picker.isRoutePickerButtonBordered = false
    return picker
  }

  func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif
