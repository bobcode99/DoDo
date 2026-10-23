//
//  MarqueeText.swift
//  PodcastAnalyzer
//
//  A single-line text that scrolls horizontally (circular left shift) when its
//  intrinsic width exceeds the available container width. Falls back to a static
//  one-line text when it fits.
//

import SwiftUI

struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var fontWeight: Font.Weight?
    var spacing: CGFloat = 40
    var velocity: CGFloat = 30 // points per second — slow enough to read along
    var pauseDuration: Double = 3 // seconds held at the start of each cycle
    var alignment: HorizontalAlignment = .leading

    @State private var intrinsicWidth: CGFloat = 0
    /// When the current lap started scrolling; nil while held at the start.
    @State private var lapStart: Date?

    var body: some View {
        baseText
            .lineLimit(1)
            .hidden()
            .overlay(alignment: Alignment(horizontal: alignment, vertical: .center)) {
                GeometryReader { proxy in
                    overlayContent(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .background {
                baseText
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { intrinsicWidth = $0 }
            }
    }

    private var baseText: Text {
        var view = Text(text).font(font)
        if let fontWeight {
            view = view.fontWeight(fontWeight)
        }
        return view
    }

    @ViewBuilder
    private func overlayContent(width: CGFloat, height: CGFloat) -> some View {
        let needsScroll = intrinsicWidth > width && width > 0
        if needsScroll {
            let total = intrinsicWidth + spacing
            let scrollDuration = max(0.1, Double(total / velocity))
            // The offset is computed from the clock each frame, and only while
            // a lap scrolls — the timeline is paused for the hold at the start.
            // A one-shot `withAnimation` to the lap's end was cheaper, but the
            // model offset then sat at the end while the render server drew the
            // motion: whenever SwiftUI redrew the bar mid-lap (the tab-bar
            // accessory switching between expanded and inline on scroll), it
            // culled the copy lying outside the clip at that end position, and
            // the title went blank for most of the lap.
            TimelineView(.animation(paused: lapStart == nil)) { context in
                let progress = lapStart.map { min(context.date.timeIntervalSince($0) / scrollDuration, 1) } ?? 0
                HStack(spacing: spacing) {
                    baseText.lineLimit(1).fixedSize()
                    baseText.lineLimit(1).fixedSize()
                }
                .offset(x: -total * progress)
                .frame(width: width, height: height, alignment: .leading)
                .clipped()
            }
            .task(id: "\(text)|\(total)|\(width)") {
                while !Task.isCancelled {
                    lapStart = nil
                    try? await Task.sleep(for: .seconds(pauseDuration))
                    guard !Task.isCancelled else { return }
                    lapStart = .now
                    try? await Task.sleep(for: .seconds(scrollDuration))
                }
            }
        } else {
            baseText
                .lineLimit(1)
                .frame(
                    width: width,
                    height: height,
                    alignment: Alignment(horizontal: alignment, vertical: .center)
                )
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        MarqueeText(
            text: "Short title",
            font: .title3,
            fontWeight: .bold,
            alignment: .center
        )
        .frame(width: 240)
        .border(.gray)

        MarqueeText(
            text: "Russia and Ukraine ceasefire talks resume amid pressure",
            font: .title3,
            fontWeight: .bold,
            alignment: .center
        )
        .frame(width: 240)
        .border(.gray)

        MarqueeText(
            text: "Episode 42 — Russia and Ukraine being shaken by recent events",
            font: .subheadline,
            fontWeight: .medium
        )
        .frame(width: 200)
        .border(.gray)
    }
    .padding()
}
