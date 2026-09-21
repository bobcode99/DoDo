//
//  PlatformUtilities.swift
//  PodcastAnalyzer
//
//  Cross-platform utilities for sharing, clipboard, and image handling
//

import SwiftUI

#if os(iOS)
import UIKit
public typealias PlatformImage = UIImage
#else
import AppKit
public typealias PlatformImage = NSImage
#endif

// MARK: - Platform Clipboard

struct PlatformClipboard {
  static var string: String? {
    get {
      #if os(iOS)
      return UIPasteboard.general.string
      #else
      return NSPasteboard.general.string(forType: .string)
      #endif
    }
    set {
      #if os(iOS)
      UIPasteboard.general.string = newValue
      #else
      NSPasteboard.general.clearContents()
      if let value = newValue {
        NSPasteboard.general.setString(value, forType: .string)
      }
      #endif
    }
  }
}

// MARK: - Platform Share Sheet

struct PlatformShareSheet {
  /// Present a share sheet with the given items
  @MainActor
  static func share(items: [Any]) {
    #if os(iOS)
    // The active scene's key window, not `.first`: with several iPad windows
    // `.first` can be a background one and the sheet appears elsewhere.
    guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?.keyWindow,
          var presenter = window.rootViewController else { return }
    // Present from the top of the stack — root refuses while any sheet (e.g.
    // the expanded player) is up, and the share sheet silently never appeared.
    while let presented = presenter.presentedViewController { presenter = presented }

    let activityVC = UIActivityViewController(
      activityItems: items,
      applicationActivities: nil
    )

    // For iPad
    if let popover = activityVC.popoverPresentationController {
      popover.sourceView = window
      popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }

    presenter.present(activityVC, animated: true)
    #else
    // macOS sharing via NSSharingServicePicker
    let picker = NSSharingServicePicker(items: items)

    // Find the key window and present from its content view
    if let window = NSApplication.shared.keyWindow,
       let contentView = window.contentView {
      let rect = NSRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
      picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
    }
    #endif
  }

  /// Share a URL
  @MainActor
  static func share(url: URL) {
    share(items: [url])
  }

  /// Share text
  @MainActor
  static func share(text: String) {
    share(items: [text])
  }
}

// MARK: - Platform Color Extensions

extension Color {
  /// System background color
  static var platformBackground: Color {
    #if os(iOS)
    return Color(UIColor.systemBackground)
    #else
    return Color(NSColor.windowBackgroundColor)
    #endif
  }

  /// Secondary system background
  static var platformSecondaryBackground: Color {
    #if os(iOS)
    return Color(UIColor.secondarySystemBackground)
    #else
    return Color(NSColor.controlBackgroundColor)
    #endif
  }

  /// Tertiary system background
  static var platformTertiaryBackground: Color {
    #if os(iOS)
    return Color(UIColor.tertiarySystemBackground)
    #else
    return Color(NSColor.underPageBackgroundColor)
    #endif
  }

  /// System gray colors
  static var platformSystemGray5: Color {
    #if os(iOS)
    return Color(UIColor.systemGray5)
    #else
    return Color(NSColor.separatorColor)
    #endif
  }

  static var platformSystemGray6: Color {
    #if os(iOS)
    return Color(UIColor.systemGray6)
    #else
    return Color(NSColor.windowBackgroundColor)
    #endif
  }
}

// MARK: - Platform Image Extensions

extension PlatformImage {
  /// Create image from SwiftUI Image data
  convenience init?(swiftUIImageData data: Data) {
    #if os(iOS)
    self.init(data: data)
    #else
    self.init(data: data)
    #endif
  }

  #if os(macOS)
  /// Convert NSImage to CGImage for compatibility
  var cgImage: CGImage? {
    var rect = NSRect(origin: .zero, size: size)
    return cgImage(forProposedRect: &rect, context: nil, hints: nil)
  }
  #endif
}

// MARK: - Platform Title Display Mode

/// Platform-independent navigation bar title display mode
nonisolated enum PlatformTitleDisplayMode {
  case automatic
  case inline
  case large
}

// MARK: - View Extensions for Platform Compatibility

extension View {
  /// Apply iOS-only navigation bar title display mode
  @ViewBuilder
  func platformNavigationBarTitleDisplayMode(_ mode: PlatformTitleDisplayMode) -> some View {
    #if os(iOS)
    switch mode {
    case .automatic:
      self.navigationBarTitleDisplayMode(.automatic)
    case .inline:
      self.navigationBarTitleDisplayMode(.inline)
    case .large:
      self.navigationBarTitleDisplayMode(.large)
    }
    #else
    self
    #endif
  }

  /// Apply toolbar title display mode
  @ViewBuilder
  func platformToolbarTitleDisplayMode() -> some View {
    #if os(iOS)
    self.toolbarTitleDisplayMode(.inlineLarge)
    #else
    self
    #endif
  }
}

// MARK: - Platform Detection

nonisolated struct Platform {
  static var isIOS: Bool {
    #if os(iOS)
    return true
    #else
    return false
    #endif
  }

  static var isMacOS: Bool {
    #if os(macOS)
    return true
    #else
    return false
    #endif
  }

  static var isVisionOS: Bool {
    #if os(visionOS)
    return true
    #else
    return false
    #endif
  }
}
