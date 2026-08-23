//
//  PermissionRow.swift
//  PodcastAnalyzer
//
//  One requestable system permission on the onboarding permissions page.
//

#if os(iOS)
import SwiftUI

struct PermissionRow: View {
  let icon: String
  let color: Color
  // LocalizedStringKey so these follow the in-app language override; see
  // FeatureRow for why `String(localized:)` is wrong here.
  let title: LocalizedStringKey
  let description: LocalizedStringKey
  /// Reflects the live OS authorization — the row mirrors it, it isn't owned here.
  let isOn: Bool
  let onRequest: () -> Void

  @ScaledMetric private var iconWidth: Double = 34

  var body: some View {
    // A Button, not a Toggle: the source of truth is the OS permission, and a
    // granted permission can't be revoked in-app. A Toggle announced itself to
    // VoiceOver as switchable off, which silently did nothing.
    Button(action: onRequest) {
      HStack(spacing: 14) {
        Image(systemName: icon)
          .font(.title2)
          .foregroundStyle(color)
          .frame(width: iconWidth)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.subheadline)
            .bold()
            .foregroundStyle(.primary)
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer(minLength: 8)

        if isOn {
          Label("Allowed", systemImage: "checkmark.circle.fill")
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(color)
        } else {
          Text("Allow")
            .font(.subheadline)
            .bold()
            .foregroundStyle(color)
        }
      }
      .padding(14)
      .background(.regularMaterial, in: .rect(cornerRadius: 14))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isOn)
  }
}

#Preview {
  VStack(spacing: 12) {
    PermissionRow(
      icon: "waveform",
      color: .purple,
      title: "Speech Recognition",
      description: "On-device transcripts with Apple Speech",
      isOn: false,
      onRequest: {}
    )
    PermissionRow(
      icon: "bell.badge.fill",
      color: .red,
      title: "Notifications",
      description: "Get notified about new episodes",
      isOn: true,
      onRequest: {}
    )
  }
  .padding()
}

#endif
