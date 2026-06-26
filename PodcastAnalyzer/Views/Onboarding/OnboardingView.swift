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
  @Environment(\.openURL) private var openURL

  var body: some View {
    TabView(selection: $currentPage) {
      WelcomeOnboardingPage(onNext: { currentPage = 1 })
        .tag(0)
      ImportOnboardingPage(
        onImport: triggerImportShortcut,
        onSkip: { hasCompletedOnboarding = true }
      )
      .tag(1)
    }
    .tabViewStyle(.page)
    .indexViewStyle(.page(backgroundDisplayMode: .always))
    .ignoresSafeArea()
  }

  /// Completes onboarding and hands off to the "ApplePodcast To PodcastAnalyzer" shortcut.
  /// The shortcut is expected to call back via podcastanalyzer://import-podcasts?rssURLs=...
  private func triggerImportShortcut() {
    hasCompletedOnboarding = true
    if let url = URL(string: "shortcuts://run-shortcut?name=ApplePodcast%20To%20PodcastAnalyzer") {
      openURL(url)
    }
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
          .padding(16)
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
  let onImport: () -> Void
  let onSkip: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      Image(systemName: "square.and.arrow.down.fill")
        .font(.system(size: 80))
        .foregroundStyle(.blue.gradient)
        .padding(.bottom, 24)

      VStack(spacing: 10) {
        Text("Bring Your Podcasts")
          .font(.largeTitle)
          .fontWeight(.bold)
          .multilineTextAlignment(.center)

        Text("Already subscribed in Apple Podcasts?\nImport all your shows in seconds.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
      }

      Spacer()

      VStack(spacing: 12) {
        Button(action: onImport) {
          Label("Import from Apple Podcasts", systemImage: "square.and.arrow.down")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.blue, in: .rect(cornerRadius: 14))
        }

        Button("Start Fresh", action: onSkip)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.vertical, 8)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 52)
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
