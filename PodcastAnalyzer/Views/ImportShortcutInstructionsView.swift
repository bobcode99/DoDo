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

  /// The signed shortcut file in the repo; opening it offers to add it to Shortcuts.
  private let shortcutLink = URL(string: "https://github.com/bobcode99/DoDo/raw/refs/heads/main/Shortcuts/ApplePodcast%20To%20DoDo.shortcut")!
  /// Runs the installed shortcut by name — the file name it was added under.
  private let runLink = URL(string: "shortcuts://run-shortcut?name=ApplePodcast%20To%20DoDo")!

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      StepRow(number: 1, title: "Get the shortcut") {
        Text("Tap below to open the **ApplePodcast to Dodo** shortcut in the Shortcuts app.")
        Button("Get Shortcut", systemImage: "square.and.arrow.down") {
          openURL(shortcutLink)
        }
        .buttonStyle(.accentProminent)
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
  /// `LocalizedStringKey`, not `String`: a `String(localized:)` title reads the
  /// *system* language and ignores the in-app language picker.
  let title: LocalizedStringKey
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
