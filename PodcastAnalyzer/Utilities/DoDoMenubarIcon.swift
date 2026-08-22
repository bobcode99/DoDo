//
//  DoDoMenubarIcon.swift
//  PodcastAnalyzer
//
//  The menubar mark: the DoDo cactus artwork itself.
//
//  This started as a drawn template — a disc cut into eight wedges with a dot
//  in each — because menubar images are conventionally templates, where macOS
//  keeps only the alpha and tints it. That reads as the Kubernetes helm, which
//  is not a resemblance any podcast app wants, and it was a redrawing of the
//  logo rather than the logo.
//
//  So: the real artwork, in colour. A colour status item is ordinary (Slack,
//  Dropbox), and the muted green survives both menubars — checked by rendering
//  it at 36px, the true retina size, over white and over black. The ribs and
//  areoles still read at that size, which is the whole reason the shape works
//  this small.
//

#if os(macOS)

import AppKit
import OSLog

enum DoDoMenubarIcon {
  private static let logger = Logger(subsystem: "com.podcast.analyzer", category: "MenubarIcon")

  /// Built once per state. `refresh()` runs on every observation tick, and the
  /// source art is a 1024px PNG — rescaling it a few times a second to fill an
  /// 18pt slot is pure waste.
  private static var cache: [Bool: NSImage] = [:]

  static func image(size: CGFloat = 18, showsBadge: Bool = false) -> NSImage {
    if let cached = cache[showsBadge], cached.size.width == size { return cached }
    let built = build(size: size, showsBadge: showsBadge)
    cache[showsBadge] = built
    return built
  }

  private static func build(size: CGFloat, showsBadge: Bool) -> NSImage {
    guard let art = NSImage(named: "DoDoLogo") else {
      // Never expected — the imageset ships in the app's asset catalog — but a
      // missing icon must not cost the user the menu behind it.
      logger.error("DoDoLogo missing from the asset catalog; falling back")
      let fallback = NSImage(
        systemSymbolName: "circle.dotted.circle",
        accessibilityDescription: "DoDo") ?? NSImage()
      fallback.isTemplate = true
      return fallback
    }

    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
      art.draw(
        in: rect, from: .zero, operation: .sourceOver, fraction: 1,
        respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
      if showsBadge { drawBadge(in: rect) }
      return true
    }
    // Colour, not a template: tinting this to a flat silhouette would throw
    // away the ribs and dots that make it legible at all.
    image.isTemplate = false
    return image
  }

  /// Server trouble. A red pip in a punched-out ring at the lower trailing
  /// corner, kept fully inside the bounds — hung off the edge it gets clipped
  /// by the image rect and reads as a bite out of the mark.
  private static func drawBadge(in rect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    let side = min(rect.width, rect.height)
    let badge = side * 0.34
    let origin = NSPoint(x: rect.maxX - badge, y: rect.minY)
    let ring = side * 0.05

    ctx.saveGState()
    ctx.setBlendMode(.destinationOut)
    NSColor.black.setFill()
    NSBezierPath(
      ovalIn: NSRect(x: origin.x, y: origin.y, width: badge, height: badge)
        .insetBy(dx: -ring, dy: -ring)
    ).fill()
    ctx.restoreGState()

    NSColor.systemRed.setFill()
    NSBezierPath(ovalIn: NSRect(x: origin.x, y: origin.y, width: badge, height: badge)).fill()
  }
}

#endif
