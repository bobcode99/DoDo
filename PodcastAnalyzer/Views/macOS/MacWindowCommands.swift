//
//  MacWindowCommands.swift
//  PodcastAnalyzer
//
//  Window ▸ Main Window, and the scene's openWindow action for AppKit callers.
//

#if os(macOS)
import SwiftUI

/// Commands exist before any window does, so this is where `MacBackgroundMode`
/// gets the scene's `openWindow` for launch, Dock reopen and the menubar item.
struct MacWindowCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    let _ = (MacBackgroundMode.openMainWindow = openWindow)

    CommandGroup(before: .windowList) {
      Button("Main Window", action: MacBackgroundMode.presentMainWindow)
        .keyboardShortcut("0")
    }
  }
}
#endif
