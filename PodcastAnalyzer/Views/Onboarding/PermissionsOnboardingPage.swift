//
//  PermissionsOnboardingPage.swift
//  PodcastAnalyzer
//
//  Onboarding step that requests speech recognition and notifications, and
//  deep-links to Settings for Background App Refresh.
//

#if os(iOS)
import Speech
import SwiftUI

struct PermissionsOnboardingPage: View {
  let onNext: () -> Void

  private let sync = BackgroundSyncManager.shared
  @State private var speechStatus = SFSpeechRecognizer.authorizationStatus()
  // Background App Refresh is a system setting — we can read it but not request it.
  @State private var backgroundRefresh = UIApplication.shared.backgroundRefreshStatus

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        Image(systemName: "hand.raised.fill")
          .font(.system(size: 60))
          .foregroundStyle(.blue.gradient)
          .padding(.top, 64)
          .padding(.bottom, 16)

        VStack(spacing: 10) {
          Text("Enable Full Experience")
            .font(.largeTitle)
            .bold()
            .multilineTextAlignment(.center)

          Text("We recommend turning all of these on.\nYou stay in control — decide what to allow.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
        .padding(.bottom, 28)

        VStack(spacing: 12) {
          PermissionRow(
            icon: "waveform",
            color: .purple,
            title: "Speech Recognition",
            description: "On-device transcripts with Apple Speech",
            isOn: speechStatus == .authorized,
            onRequest: requestSpeech
          )
          PermissionRow(
            icon: "bell.badge.fill",
            color: .red,
            title: "Notifications",
            description: "Get notified about new episodes",
            isOn: sync.notificationPermissionStatus == .authorized,
            onRequest: requestNotifications
          )
          PermissionRow(
            icon: "arrow.clockwise.circle.fill",
            color: .green,
            title: "Background App Refresh",
            description: "Fetch new episodes while you're away",
            isOn: backgroundRefresh == .available,
            // OS-controlled system setting — can't request, only deep-link.
            onRequest: openSettings
          )
        }
        .padding(.horizontal, 24)

        // Styling on the label — full pill tappable, not just the text.
        Button(action: onNext) {
          Text("Continue")
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.blue, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 52)
      }
    }
    .task { await sync.checkNotificationPermission() }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
    ) { _ in
      // Returning from Settings — pick up any changes the user made there.
      refreshStatuses()
    }
  }

  private func refreshStatuses() {
    speechStatus = SFSpeechRecognizer.authorizationStatus()
    backgroundRefresh = UIApplication.shared.backgroundRefreshStatus
    Task { await sync.checkNotificationPermission() }
  }

  private func requestSpeech() {
    // Only the first, undetermined state can prompt. Once denied/restricted the
    // system won't show the dialog again — route to Settings instead.
    switch speechStatus {
    case .notDetermined:
      // requestAuthorizationStatus() is the nonisolated wrapper — a completion
      // closure formed here (MainActor context) would be inferred @MainActor and
      // crash with dispatch_assert_queue when TCC invokes it on a background
      // queue. The Task body stays on the MainActor for the @State write.
      Task {
        speechStatus = await SFSpeechRecognizer.requestAuthorizationStatus()
      }
    case .denied, .restricted:
      openSettings()
    default:
      break
    }
  }

  private func requestNotifications() {
    switch sync.notificationPermissionStatus {
    case .notDetermined:
      sync.requestNotificationPermission()
    case .denied:
      openSettings()
    default:
      break
    }
  }

  private func openSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) {
      UIApplication.shared.open(url)
    }
  }
}

#Preview {
  PermissionsOnboardingPage(onNext: {})
}

#endif
