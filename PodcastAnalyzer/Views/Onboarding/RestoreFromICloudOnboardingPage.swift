//
//  RestoreFromICloudOnboardingPage.swift
//  PodcastAnalyzer
//
//  Final onboarding page for a returning user: restores the subscriptions
//  already synced to their Apple ID instead of asking for a manual import.
//

#if os(iOS)
import SwiftUI

struct RestoreFromICloudOnboardingPage: View {
  let onDone: () -> Void
  @State private var model = ICloudRestoreModel()

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      Image(systemName: "icloud.and.arrow.down.fill")
        .font(.system(size: 64))
        .foregroundStyle(.blue.gradient)
        .padding(.bottom, 18)

      VStack(spacing: 10) {
        Text("Welcome Back")
          .font(.largeTitle)
          .bold()
          .multilineTextAlignment(.center)

        Text(model.isRestoring
          ? "Restoring your subscriptions from iCloud…"
          : "Restored ^[\(model.restoredCount) podcast](inflect: true) from iCloud.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
      }
      .padding(.top, 4)

      if model.isRestoring {
        ProgressView()
          .padding(.top, 24)
      }

      Spacer()

      Button(action: onDone) {
        Text(model.isRestoring ? "Skip" : "Continue")
          .font(.headline)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(.blue, in: .rect(cornerRadius: 14))
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 24)
      .padding(.bottom, 52)
    }
    .task { await model.restore() }
  }
}

#Preview {
  RestoreFromICloudOnboardingPage(onDone: {})
}

#endif
