//
//  ImportShortcutInstructionsView.swift
//  PodcastAnalyzer
//
//  Step-by-step guide for importing Apple Podcasts subscriptions via the
//  "ApplePodcast to Dodo" Shortcut. Most users don't have the shortcut yet,
//  so we walk them through installing it before running it.
//

import SwiftUI

struct ImportShortcutInstructionsView: View {
  @Environment(\.openURL) private var openURL

  /// iCloud link to the "ApplePodcast to Dodo" shortcut.
  private let shortcutLink = URL(string: "https://www.icloud.com/shortcuts/6063d502abc24d92951f4d8dbcfddd64")!
  /// Runs the installed shortcut by name.
  private let runLink = URL(string: "shortcuts://run-shortcut?name=ApplePodcast%20to%20Dodo")!

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      StepRow(number: 1, title: "Get the shortcut") {
        Text("Tap below to open the **ApplePodcast to Dodo** shortcut in the Shortcuts app.")
        Button("Get Shortcut", systemImage: "square.and.arrow.down") {
          openURL(shortcutLink)
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 2)
      }

      StepRow(number: 2, title: "Add it") {
        Text("Tap **Add Shortcut** to install it on your device.")
      }

      StepRow(number: 3, title: "Find it") {
        Text("In the Shortcuts app, open **All Shortcuts**.")
      }

      StepRow(number: 4, title: "Run it") {
        Text("Tap **ApplePodcast to Dodo** to import all your shows.")
        Button("Run Shortcut", systemImage: "play.fill") {
          openURL(runLink)
        }
        .buttonStyle(.bordered)
        .padding(.top, 2)
      }
    }
  }
}

private struct StepRow<Content: View>: View {
  let number: Int
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Text("\(number)")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(.white)
        .frame(width: 28, height: 28)
        .background(.blue, in: .circle)

      VStack(alignment: .leading, spacing: 6) {
        Text(title)
          .font(.headline)
        content
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}

#Preview {
  ImportShortcutInstructionsView()
    .padding()
}
