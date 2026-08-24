//
//  WelcomeOnboardingPage.swift
//  PodcastAnalyzer
//
//  First onboarding page: what DoDo is, and what it does.
//

#if os(iOS)
import SwiftUI

struct WelcomeOnboardingPage: View {
  let onNext: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      Image("dodo-real")
        .resizable()
        .scaledToFill()
        .frame(width: 116, height: 116)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
        .padding(.bottom, 28)
        .accessibilityHidden(true)

      VStack(spacing: 6) {
        Text("Welcome to\nDoDo")
          .font(.largeTitle)
          .bold()
          .multilineTextAlignment(.center)

        Text("a Podcast Analyzer")
          .font(.callout)
          .italic()
          .foregroundStyle(.secondary)

        Text("Listen, download, and analyze podcasts\nwith AI-powered insights.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.top, 6)
      }

      Spacer()

      VStack(spacing: 16) {
        FeatureRow(
          icon: "arrow.down.circle.fill",
          color: .green,
          title: "Download Episodes",
          description: "Save episodes for offline listening"
        )
        FeatureRow(
          icon: "text.bubble.fill",
          color: .purple,
          title: "AI Transcripts",
          description: "On-device speech-to-text with Whisper"
        )
        FeatureRow(
          icon: "sparkles",
          color: .orange,
          title: "Smart Analysis",
          description: "Summaries, highlights, and Q&A"
        )
      }
      .padding(.horizontal, 28)

      Spacer()

      VStack(spacing: 12) {
        // Styling lives on the label so the whole pill is tappable — modifiers
        // outside Button only decorate; the hit target would stay text-sized.
        Button(action: onNext) {
          Text("Get Started")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.blue, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)

        Text("Named after 兜 (Dōu), the Sand Dollar Cactus.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 40)
    }
  }
}

#Preview {
  WelcomeOnboardingPage(onNext: {})
}

#endif
