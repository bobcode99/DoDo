//
//  ImportOnboardingPage.swift
//  PodcastAnalyzer
//
//  Final onboarding page for a new user: install the export shortcut and
//  bring subscriptions over from Apple Podcasts, or start fresh.
//

#if os(iOS)
import SwiftUI

struct ImportOnboardingPage: View {
  let onSkip: () -> Void
  // Singleton read directly rather than held in @State — @Observable tracks
  // property reads in body on its own, and @State would imply ownership.
  private var importManager: PodcastImportManager { .shared }

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
            .bold()
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
    // Safety net for the shortcut-driven import: when it finishes on this
    // page, setup is done — dismiss onboarding instead of making the user
    // tap "Start Fresh". The intent itself also completes the flag; this
    // covers any path that reaches PodcastImportManager directly.
    .onChange(of: importManager.isImporting) { wasImporting, isImporting in
      if wasImporting && !isImporting {
        onSkip()
      }
    }
  }
}

#Preview {
  ImportOnboardingPage(onSkip: {})
}

#endif
