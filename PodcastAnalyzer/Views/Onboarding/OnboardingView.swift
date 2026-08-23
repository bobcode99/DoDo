//
//  OnboardingView.swift
//  PodcastAnalyzer
//
//  First-launch onboarding guide. Shown once; skippable.
//  After completion or skip the flag is persisted via AppStorage
//  so the screen never appears again.
//

#if os(iOS)
import CoreData
import SwiftUI

struct OnboardingView: View {
  @AppStorage(Constants.hasCompletedOnboardingKey) private var hasCompletedOnboarding = false
  @State private var currentPage = OnboardingPage.welcome
  /// nil = not checked yet; true = this Apple ID already has subscriptions in
  /// iCloud, so the last page restores instead of asking for an import.
  @State private var hasCloudSubscriptions: Bool?

  var body: some View {
    TabView(selection: $currentPage) {
      WelcomeOnboardingPage(onNext: { currentPage = .region })
        .tag(OnboardingPage.welcome)
      RegionOnboardingPage(onNext: { currentPage = .permissions })
        .tag(OnboardingPage.region)
      PermissionsOnboardingPage(onNext: { currentPage = .transcription })
        .tag(OnboardingPage.permissions)
      TranscriptionOnboardingPage(onNext: { currentPage = .finish })
        .tag(OnboardingPage.transcription)
      if hasCloudSubscriptions == true {
        RestoreFromICloudOnboardingPage(onDone: completeOnboarding)
          .tag(OnboardingPage.finish)
      } else {
        ImportOnboardingPage(onSkip: completeOnboarding)
          .tag(OnboardingPage.finish)
      }
    }
    .tabViewStyle(.page)
    .indexViewStyle(.page(backgroundDisplayMode: .always))
    .ignoresSafeArea()
    .task {
      // A returning user's Apple ID already has subscriptions in iCloud —
      // skip the manual "bring your podcasts" step and restore instead.
      refreshCloudSubscriptionState()
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
      // On a fresh install the mirror is still empty when this view appears —
      // CloudKit's first import lands seconds to minutes later. Checking only
      // once meant a returning user always saw the manual import page.
      refreshCloudSubscriptionState()
    }
  }

  private func refreshCloudSubscriptionState() {
    guard hasCloudSubscriptions != true else { return }
    hasCloudSubscriptions = SubscriptionSyncCoordinator.shared.hasCloudSubscriptions()
  }

  private func completeOnboarding() {
    hasCompletedOnboarding = true
  }
}

#Preview {
  OnboardingView()
}

#endif
