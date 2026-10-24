//
//  OnboardingPageScaffold.swift
//  PodcastAnalyzer
//
//  Keeps an onboarding page in a readable column and lets it scroll when its
//  content outgrows the window: short windows, large text sizes, or a wide,
//  short display. The page's own spacers still spread it out when it fits.
//

#if os(iOS)
import SwiftUI

struct OnboardingPageScaffold<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    ViewThatFits(in: .vertical) {
      content
        .onboardingColumn()
      ScrollView {
        content
          .onboardingColumn()
      }
      .scrollBounceBehavior(.basedOnSize)
    }
  }
}

extension View {
  /// Wide enough for the button and rows at iPhone width, narrow enough that an
  /// iPad window does not stretch them edge to edge.
  func onboardingColumn() -> some View {
    frame(maxWidth: 560)
  }
}

#endif
