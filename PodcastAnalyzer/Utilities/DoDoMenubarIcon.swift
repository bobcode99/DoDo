//
//  DoDoMenubarIcon.swift
//  PodcastAnalyzer
//
//  The menubar mark, drawn rather than shipped as an image.
//
//  The status item used to borrow SF Symbols' `network` globe, which said
//  "some app is doing networking" and nothing about DoDo — and since headless
//  mode now means "the app is running with no window", this glyph is the app's
//  only presence on screen, not a server indicator.
//
//  Drawn, not scaled from dodogood.png, because a menubar image has to be a
//  template: macOS keeps the alpha and throws the colour away so it can tint
//  for light, dark, and the highlighted state. The artwork's alpha is a filled
//  disc, so scaling it down would produce a featureless blob. This reproduces
//  the same mark — a ribbed cactus seen from above, areoles along the ribs —
//  in alpha, at whatever size the menubar happens to be.
//

#if os(macOS)

import AppKit

enum DoDoMenubarIcon {
  /// Eight ribs, not the artwork's ten. At the ~18pt the menubar gives us, ten
  /// cuts sit under two points apart and mush into grey.
  private static let ribCount = 8

  static func image(size: CGFloat = 18, showsBadge: Bool = false) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
      draw(in: rect.insetBy(dx: 0.5, dy: 0.5), showsBadge: showsBadge)
      return true
    }
    // Without this the glyph stays black in dark mode and never inverts when
    // the menu is open.
    image.isTemplate = true
    return image
  }

  private static func draw(in rect: NSRect, showsBadge: Bool) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }

    let side = min(rect.width, rect.height)
    let radius = side / 2
    let center = NSPoint(x: rect.midX, y: rect.midY)

    NSColor.black.setFill()
    NSBezierPath(
      ovalIn: NSRect(
        x: center.x - radius, y: center.y - radius,
        width: radius * 2, height: radius * 2)
    ).fill()

    // The ribs and areoles are cut out of the disc rather than drawn on top:
    // in a template image only alpha survives, so "lighter" has to mean
    // "absent".
    ctx.saveGState()
    ctx.setBlendMode(.destinationOut)
    NSColor.black.setStroke()
    NSColor.black.setFill()

    let ribWidth = max(side * 0.064, 0.8)
    for rib in 0..<ribCount {
      let angle = (CGFloat(rib) / CGFloat(ribCount)) * .pi * 2 - .pi / 2
      let path = NSBezierPath()
      path.move(
        to: NSPoint(
          x: center.x + cos(angle) * radius * 0.12,
          y: center.y + sin(angle) * radius * 0.12))
      path.line(
        to: NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
      path.lineWidth = ribWidth
      path.lineCapStyle = .round
      path.stroke()
    }

    let dot = max(side * 0.085, 1)
    for rib in 0..<ribCount {
      let angle = ((CGFloat(rib) + 0.5) / CGFloat(ribCount)) * .pi * 2 - .pi / 2
      let distance = radius * 0.55
      NSBezierPath(
        ovalIn: NSRect(
          x: center.x + cos(angle) * distance - dot / 2,
          y: center.y + sin(angle) * distance - dot / 2,
          width: dot, height: dot)
      ).fill()
    }
    ctx.restoreGState()

    guard showsBadge else { return }
    // Server trouble. A notch bitten out of the lower-trailing edge, then a
    // filled pip inside it, so the badge survives tinting and reads against
    // both a light and a dark menubar.
    let badge = side * 0.32
    // Fully inside the bounds: a badge hung off the corner is clipped by the
    // image rect and reads as a bite taken out of the mark.
    let origin = NSPoint(x: rect.maxX - badge, y: rect.minY)
    let gap = side * 0.05
    ctx.saveGState()
    ctx.setBlendMode(.destinationOut)
    NSColor.black.setFill()
    NSBezierPath(
      ovalIn: NSRect(x: origin.x, y: origin.y, width: badge, height: badge)
        .insetBy(dx: -gap, dy: -gap)
    ).fill()
    ctx.restoreGState()

    NSColor.black.setFill()
    NSBezierPath(ovalIn: NSRect(x: origin.x, y: origin.y, width: badge, height: badge)).fill()
  }
}

#endif
