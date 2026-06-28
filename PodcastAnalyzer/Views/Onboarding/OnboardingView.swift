//
//  OnboardingView.swift
//  PodcastAnalyzer
//
//  First-launch onboarding guide. Shown once; skippable.
//  After completion or skip the flag is persisted via AppStorage
//  so the screen never appears again.
//

#if os(iOS)
import SwiftUI

struct OnboardingView: View {
  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
  @State private var currentPage = 0

  var body: some View {
    TabView(selection: $currentPage) {
      WelcomeOnboardingPage(onNext: { currentPage = 1 })
        .tag(0)
      ImportOnboardingPage(onSkip: { hasCompletedOnboarding = true })
        .tag(1)
    }
    .tabViewStyle(.page)
    .indexViewStyle(.page(backgroundDisplayMode: .always))
    .ignoresSafeArea()
  }
}

// MARK: - Welcome Page

private struct WelcomeOnboardingPage: View {
  let onNext: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      ZStack {
        RoundedRectangle(cornerRadius: 26)
          .fill(Color(.displayP3, red: 0.137, green: 0.216, blue: 0.188).gradient)
        Image("DoDoLogo")
          .resizable()
          .scaledToFit()
          .padding(8)
      }
      .frame(width: 116, height: 116)
      .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
      .padding(.bottom, 28)

      VStack(spacing: 6) {
        Text("Welcome to\nDoDo")
          .font(.largeTitle)
          .fontWeight(.bold)
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
        Button("Get Started", action: onNext)
          .font(.headline)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(.blue, in: .rect(cornerRadius: 14))

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

// MARK: - Import Page

private struct ImportOnboardingPage: View {
  let onSkip: () -> Void

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        Image(systemName: "square.and.arrow.down.fill")
          .font(.system(size: 64))
          .foregroundStyle(.blue.gradient)
          .padding(.top, 72)
          .padding(.bottom, 18)

        VStack(spacing: 10) {
          Text("Bring Your Podcasts")
            .font(.largeTitle)
            .fontWeight(.bold)
            .multilineTextAlignment(.center)

          Text("Already subscribed in Apple Podcasts?\nInstall the shortcut, then import your shows.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 28)

        ImportShortcutInstructionsView()
          .padding(.horizontal, 28)

        Button("Start Fresh", action: onSkip)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.top, 28)
          .padding(.bottom, 52)
      }
    }
  }
}

// MARK: - Feature Row

private struct FeatureRow: View {
  let icon: String
  let color: Color
  let title: String
  let description: String

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundStyle(color)
        .frame(width: 36)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.semibold)
        Text(description)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
  }
}

#Preview {
  OnboardingView()
}

#endif
