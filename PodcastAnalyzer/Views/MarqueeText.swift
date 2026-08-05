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
    var fontWeight: Font.Weight? = nil
    var spacing: CGFloat = 40
    var velocity: CGFloat = 40 // points per second
    var pauseDuration: Double = 3 // seconds held at the start of each cycle
    var alignment: HorizontalAlignment = .leading

    @State private var intrinsicWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        baseText
            .lineLimit(1)
            .hidden()
            .overlay(alignment: Alignment(horizontal: alignment, vertical: .center)) {
                GeometryReader { proxy in
                    overlayContent(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .background(
                baseText
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { intrinsicWidth = proxy.size.width }
                                .onChange(of: proxy.size.width) { _, newValue in
                                    intrinsicWidth = newValue
                                }
                        }
                    )
            )
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
            HStack(spacing: spacing) {
                baseText.lineLimit(1).fixedSize()
                baseText.lineLimit(1).fixedSize()
            }
            .offset(x: offset)
            .frame(width: width, height: height, alignment: .leading)
            .clipped()
            // One `withAnimation` per cycle instead of a `TimelineView(.animation)`
            // that re-evaluated this body every display frame (120Hz on ProMotion)
            // for as long as the view was on screen. The render server interpolates
            // the offset; SwiftUI only runs the body twice a cycle.
            .task(id: "\(text)|\(total)|\(width)") {
                while !Task.isCancelled {
                    offset = 0
                    try? await Task.sleep(for: .seconds(pauseDuration))
                    guard !Task.isCancelled else { return }
                    withAnimation(.linear(duration: scrollDuration)) {
                        offset = -total
                    }
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
