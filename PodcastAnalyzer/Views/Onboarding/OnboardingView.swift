//
//  OnboardingView.swift
//  PodcastAnalyzer
//
//  First-launch onboarding guide. Shown once; skippable.
//  After completion or skip the flag is persisted via AppStorage
//  so the screen never appears again.
//

#if os(iOS)
import Speech
import SwiftUI
import UIKit

struct OnboardingView: View {
  @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
  @State private var currentPage = 0
  /// nil = not checked yet (show nothing conclusive on page 4 until we know);
  /// checked once on appear since it only needs to reflect state at launch.
  @State private var hasCloudSubscriptions: Bool?

  var body: some View {
    TabView(selection: $currentPage) {
      WelcomeOnboardingPage(onNext: { currentPage = 1 })
        .tag(0)
      RegionOnboardingPage(onNext: { currentPage = 2 })
        .tag(1)
      PermissionsOnboardingPage(onNext: { currentPage = 3 })
        .tag(2)
      TranscriptionOnboardingPage(onNext: { currentPage = 4 })
        .tag(3)
      if hasCloudSubscriptions == true {
        RestoreFromICloudOnboardingPage(onDone: { hasCompletedOnboarding = true })
          .tag(4)
      } else {
        ImportOnboardingPage(onSkip: { hasCompletedOnboarding = true })
          .tag(4)
      }
    }
    .tabViewStyle(.page)
    .indexViewStyle(.page(backgroundDisplayMode: .always))
    .ignoresSafeArea()
    .task {
      // A returning user's Apple ID already has subscriptions in iCloud —
      // skip the manual "bring your podcasts" step and restore instead.
      hasCloudSubscriptions = SubscriptionSyncCoordinator.shared.hasCloudSubscriptions()
    }
  }
}

// MARK: - Restore From iCloud Page

private struct RestoreFromICloudOnboardingPage: View {
  let onDone: () -> Void
  @State private var isRestoring = true
  @State private var restoredCount = 0

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
          .fontWeight(.bold)
          .multilineTextAlignment(.center)

        Text(isRestoring
          ? "Restoring your subscriptions from iCloud…"
          : "Restored \(restoredCount) podcast\(restoredCount == 1 ? "" : "s") from iCloud.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 32)
      }
      .padding(.top, 4)

      if isRestoring {
        ProgressView()
          .padding(.top, 24)
      }

      Spacer()

      Button(action: onDone) {
        Text(isRestoring ? "Skip" : "Continue")
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
    .task {
      let rssURLs = SubscriptionSyncCoordinator.shared.cloudSubscriptionRSSURLs()
      restoredCount = rssURLs.count
      await PodcastImportManager.shared.importPodcasts(from: rssURLs)
      // Suppress the import sheet this triggers — this page has its own
      // progress UI, and the sheet's presentation context is the base
      // ContentView underneath this fullScreenCover.
      PodcastImportManager.shared.dismissImportSheet()
      isRestoring = false
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
          title: String(localized: "Download Episodes"),
          description: String(localized: "Save episodes for offline listening")
        )
        FeatureRow(
          icon: "text.bubble.fill",
          color: .purple,
          title: String(localized: "AI Transcripts"),
          description: String(localized: "On-device speech-to-text with Whisper")
        )
        FeatureRow(
          icon: "sparkles",
          color: .orange,
          title: String(localized: "Smart Analysis"),
          description: String(localized: "Summaries, highlights, and Q&A")
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

// MARK: - Transcription Page

private struct TranscriptionOnboardingPage: View {
  let onNext: () -> Void

  var body: some View {
    Form {
      Section {
        VStack(spacing: 10) {
          Image(systemName: "text.bubble.fill")
            .font(.system(size: 52))
            .foregroundStyle(.purple.gradient)
          Text("Transcription")
            .font(.largeTitle)
            .fontWeight(.bold)
          Text("Apple Speech transcribes on-device with no setup. For faster, higher-quality transcripts, point DoDo at a Yap server on your network.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
      }

      // Reuse the Settings section: URL, optional API key, Test Connection.
      YapServerSection()

      Section {
        Button(action: onNext) {
          Text("Continue")
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
        }
      } footer: {
        Text("Optional — you can set this up anytime in Settings. Swipe to skip.")
      }
    }
  }
}

// MARK: - Permissions Page

private struct PermissionsOnboardingPage: View {
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
            .fontWeight(.bold)
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
            title: String(localized: "Speech Recognition"),
            description: String(localized: "On-device transcripts with Apple Speech"),
            isOn: speechStatus == .authorized,
            onRequest: requestSpeech
          )
          PermissionRow(
            icon: "bell.badge.fill",
            color: .red,
            title: String(localized: "Notifications"),
            description: String(localized: "Get notified about new episodes"),
            isOn: sync.notificationPermissionStatus == .authorized,
            onRequest: requestNotifications
          )
          PermissionRow(
            icon: "arrow.clockwise.circle.fill",
            color: .green,
            title: String(localized: "Background App Refresh"),
            description: String(localized: "Fetch new episodes while you're away"),
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
      speechStatus = SFSpeechRecognizer.authorizationStatus()
      backgroundRefresh = UIApplication.shared.backgroundRefreshStatus
      Task { await sync.checkNotificationPermission() }
    }
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

// MARK: - Permission Row

private struct PermissionRow: View {
  let icon: String
  let color: Color
  let title: String
  let description: String
  /// Reflects the live OS authorization — the toggle mirrors it, it isn't owned here.
  let isOn: Bool
  let onRequest: () -> Void

  var body: some View {
    // ponytail: get/set binding, not @State — the source of truth is the OS
    // permission, not local state. Flipping on fires the request; the OS decides
    // the real value and `isOn` snaps to it on the next status refresh. A granted
    // permission can't be revoked in-app, so flip-off is a no-op.
    Toggle(isOn: Binding(get: { isOn }, set: { if $0 { onRequest() } })) {
      HStack(spacing: 14) {
        Image(systemName: icon)
          .font(.title2)
          .foregroundStyle(color)
          .frame(width: 34)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .tint(color)
    .padding(14)
    .background(.regularMaterial, in: .rect(cornerRadius: 14))
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

// MARK: - Region Page

/// Which countries' charts Home should offer.
///
/// The device region is already ticked when this appears, so the page is
/// skippable — it exists to let someone who follows, say, Taiwanese and US
/// shows set both up front rather than discovering the switcher later.
private struct RegionOnboardingPage: View {
  let onNext: () -> Void

  @State private var regions = DiscoveryRegions.shared

  /// A short, broad list. The full 174 live in Settings; offering them here
  /// would turn a setup step into a scroll.
  private var suggestions: [Storefront] {
    let codes = [Constants.defaultRegion, "us", "gb", "tw", "jp", "kr", "de", "fr", "ca", "au"]
    var seen = Set<String>()
    return codes
      .filter { seen.insert($0).inserted }
      .compactMap { Storefront.named($0) }
  }

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      Image(systemName: "globe")
        .font(.system(size: 64))
        .foregroundStyle(.tint)
        .padding(.bottom, 24)

      Text("Where do you listen?")
        .font(.title.bold())
        .multilineTextAlignment(.center)

      Text("Pick the countries whose charts you want on Home. You can change this any time in Settings.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .padding(.top, 8)

      ScrollView {
        VStack(spacing: 8) {
          ForEach(suggestions) { region in
            let isOn = regions.enabled.contains(region.code)
            Button {
              regions.toggle(region.code)
            } label: {
              HStack {
                Text(region.flag).font(.title2)
                Text(region.name)
                  .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 10)
              .background(.thinMaterial, in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            // The last one can't be unticked — Home needs somewhere to look.
            .disabled(isOn && regions.enabled.count <= 1)
          }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
      }
      .frame(maxHeight: 320)

      Spacer()

      Button(action: onNext) {
        Text("Continue")
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
      }
      .buttonStyle(.accentProminent)
      .padding(.horizontal, 32)
      .padding(.bottom, 60)
    }
  }
}

#endif
