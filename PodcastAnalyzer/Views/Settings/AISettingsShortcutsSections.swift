//
//  AISettingsShortcutsSections.swift
//  PodcastAnalyzer
//
//  Apple PCC (Shortcuts) configuration sections of AISettingsView.
//

import SwiftUI

struct AISettingsShortcutsSections: View {
    private let shortcuts = ShortcutsAIService.shared

    /// Ready-made AI shortcuts in the repo. Each name must match the file name,
    /// which is what the shortcut is called once added.
    private static let exampleShortcuts = ["DoDo-WithAIViaGpt", "DoDo-WithChatGpt"]
    private static let shortcutsFolder = URL(string: "https://github.com/bobcode99/DoDo/tree/main/Shortcuts")!

    @Environment(\.openURL) private var openURL

    @Bindable private var settings = AISettingsManager.shared
    @State private var newShortcutName: String = ""
    @State private var isAddingShortcut: Bool = false

    var body: some View {
        // Section 1: info
        Section {
            Label {
                Text("No API key needed!")
                    .font(.subheadline)
                    .fontWeight(.medium)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Text("Shortcuts calls your configured shortcut to process AI requests. You can use any AI provider (Apple Intelligence, ChatGPT, Gemini, etc.) inside your shortcut.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Shortcut Configuration")
        }

        // Section 2: shortcut names list — ForEach as direct Section children
        Section {
            ForEach(shortcuts.shortcutNames, id: \.self) { name in
                let isActive = shortcuts.shortcutName == name
                HStack(spacing: 12) {
                    Button {
                        shortcuts.shortcutName = name
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isActive ? .blue : .secondary)
                                .font(.title3)
                                .animation(.easeInOut(duration: 0.15), value: shortcuts.shortcutName)
                                .accessibilityHidden(true)
                            Text(name)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isActive ? .isSelected : [])

                    if shortcuts.shortcutNames.count > 1 {
                        Button(role: .destructive) {
                            shortcuts.removeShortcutName(name)
                        } label: {
                            Label("Remove \(name)", systemImage: "trash")
                                .labelStyle(.iconOnly)
                                .font(.subheadline)
                                .foregroundStyle(.red.opacity(0.7))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if isAddingShortcut {
                HStack(spacing: 10) {
                    TextField("Shortcut name", text: $newShortcutName)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .onSubmit { commitAddShortcut() }
                        #endif
                    Button("Add") { commitAddShortcut() }
                        .disabled(newShortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.blue)
                    Button("Cancel") {
                        newShortcutName = ""
                        isAddingShortcut = false
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    newShortcutName = ""
                    isAddingShortcut = true
                } label: {
                    Label("Add Shortcut", systemImage: "plus.circle.fill")
                }
            }
        } header: {
            Text("Shortcuts")
        } footer: {
            Text("Tap a shortcut to make it active. Add as many as you need to switch between providers quickly.")
        }

        // Section 3: ready-made shortcuts to start from
        Section {
            ForEach(Self.exampleShortcuts, id: \.self) { name in
                Button(name, systemImage: "square.and.arrow.down") {
                    getExampleShortcut(name)
                }
            }
            Link(destination: Self.shortcutsFolder) {
                Label("View All on GitHub", systemImage: "arrow.up.right.square")
            }
        } header: {
            Text("Example Shortcuts")
        } footer: {
            Text("Download one, then tap Add Shortcut in the Shortcuts app. Its name is added to the list above and made active.")
        }

        // Section 4: open shortcuts + timeout
        Section {
            Button("Open Shortcuts App", systemImage: "square.on.square") {
                ShortcutsAIService.shared.openShortcutsApp()
            }

            HStack {
                Text("Timeout")
                Spacer()
                Picker("Timeout", selection: $settings.shortcutsTimeout) {
                    Text("60s").tag(60.0 as TimeInterval)
                    Text("120s").tag(120.0 as TimeInterval)
                    Text("180s").tag(180.0 as TimeInterval)
                    Text("300s").tag(300.0 as TimeInterval)
                }
                .pickerStyle(.menu)
            }
        } footer: {
            Text("How long to wait for Shortcuts to return a result before timing out.")
        }

        // Section 5: setup instructions
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Setup Instructions:")
                    .font(.subheadline)
                    .fontWeight(.medium)

                VStack(alignment: .leading, spacing: 4) {
                    instructionRow(number: 1, text: "Open the Shortcuts app")
                    instructionRow(number: 2, text: "Create a new shortcut")
                    instructionRow(number: 3, text: "Add 'Get Clipboard' action")
                    instructionRow(number: 4, text: "Add 'Summarize' or 'Ask ChatGPT' action")
                    instructionRow(number: 5, text: "Set output to 'Text'")
                    instructionRow(number: 6, text: "Add 'Copy to Clipboard' action")
                    instructionRow(number: 7, text: "Name it exactly as configured above")
                }
            }

            // Tip about Ask Every Time
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("Pro Tip")
                        .font(.caption)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                }
                Text("Use 'Ask Every Time' for the Model parameter to choose between ChatGPT, Apple Intelligence, Gemini, or other models each time you run the shortcut.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.yellow.opacity(0.1))
            .clipShape(.rect(cornerRadius: 8))

            // How it works
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("How It Works")
                        .font(.caption)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                }
                Text("When you analyze a transcript, the app will automatically run your shortcut, wait for it to complete, and display the result. No manual copy/paste needed!")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.blue.opacity(0.1))
            .clipShape(.rect(cornerRadius: 8))
        } header: {
            Text("Setup Instructions")
        }
    }

    private func getExampleShortcut(_ name: String) {
        shortcuts.addShortcutName(name)
        shortcuts.shortcutName = name
        let file = "\(name).shortcut".addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        if let url = URL(string: "https://github.com/bobcode99/DoDo/raw/refs/heads/main/Shortcuts/\(file)") {
            openURL(url)
        }
    }

    private func commitAddShortcut() {
        let name = newShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        shortcuts.addShortcutName(name)
        newShortcutName = ""
        isAddingShortcut = false
    }

    private func instructionRow(number: Int, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
                .frame(width: 20, alignment: .leading)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
