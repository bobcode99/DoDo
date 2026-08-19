//
//  WatchTheme.swift
//  DoDoWatch
//
//  The watch target has no asset catalog, so `.tint` resolves to the system
//  default — a mid grey that makes the primary transport button read as
//  disabled against an OLED black screen. This is the app's own colour instead,
//  lifted from the icon's gradient (dodo.icon: display-p3 0.137 0.216 0.188)
//  and lightened to something that carries a black glyph at button size.
//

import SwiftUI

enum WatchTheme {
  /// Primary action colour. Bright enough for black text to pass contrast on it.
  static let accent = Color(.displayP3, red: 0.36, green: 0.80, blue: 0.62)
}
