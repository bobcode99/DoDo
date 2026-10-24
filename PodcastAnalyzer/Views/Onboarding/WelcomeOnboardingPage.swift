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
  @State private var languageManager = LanguageManager.shared

  var body: some View {
    OnboardingPageScaffold {
      VStack(spacing: 0) {
        Spacer()

        Image("dodo-real")
          .resizable()
          .scaledToFill()
          .frame(width: 116, height: 116)
          .clipShape(.rect(cornerRadius: 26))
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

          Text("Turn hours of podcasts\ninto minutes of insight.")
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
            title: "Listen Anywhere",
            description: "Download once, play offline — no signal needed"
          )
          FeatureRow(
            icon: "text.bubble.fill",
            color: .purple,
            title: "Every Word, Searchable",
            description: "Transcripts made on your device. Free and private."
          )
          FeatureRow(
            icon: "sparkles",
            color: .orange,
            title: "Skip the Filler",
            description: "AI summaries and key quotes — get the point in a minute"
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
    // First screen anyone sees, so the language can be fixed before reading
    // the rest; the same setting as Settings › App Language.
    .overlay(alignment: .topTrailing) {
      Menu {
        Picker("App Language", selection: $languageManager.appLanguage) {
          ForEach(LanguageManager.availableLanguages) { language in
            // Language names stay in their own language; only "System Default"
            // is translated.
            (language.id == "system" ? Text("System Default") : Text(verbatim: language.displayName))
              .tag(language.id)
          }
        }
      } label: {
        Label("Language", systemImage: "globe")
          .font(.subheadline)
          .padding(.horizontal, 12)
          .padding(.vertical, 12)
          .background(.fill.tertiary, in: .capsule)
      }
      .padding(.trailing, 20)
      .padding(.top, 8)
    }
  }
}

#Preview {
  WelcomeOnboardingPage(onNext: {})
}

#endif
