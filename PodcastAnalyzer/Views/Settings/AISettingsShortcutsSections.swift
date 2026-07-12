//
//  AISettingsShortcutsSections.swift
//  PodcastAnalyzer
//
//  Apple PCC (Shortcuts) configuration sections of AISettingsView.
//

import SwiftUI

struct AISettingsShortcutsSections: View {
    private let shortcuts = ShortcutsAIService.shared

    @Bindable private var settings = AISettingsManager.shared
    @State private var newShortcutName: String = ""
    @State private var isAddingShortcut: Bool = false

    var body: some View {
        // Section 1: info
        Section {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("No API key needed!")
                    .font(.subheadline)
                    .fontWeight(.medium)
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
                HStack(spacing: 12) {
                    Image(systemName: shortcuts.shortcutName == name ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(shortcuts.shortcutName == name ? .blue : .secondary)
                        .font(.system(size: 18))
                        .animation(.easeInOut(duration: 0.15), value: shortcuts.shortcutName)
                    Text(name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if shortcuts.shortcutNames.count > 1 {
                        Button(role: .destructive) {
                            shortcuts.removeShortcutName(name)
                        } label: {
                            Image(systemName: "trash")
                                .font(.subheadline)
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    shortcuts.shortcutName = name
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

        // Section 3: open shortcuts + timeout
        Section {
            Button(action: {
                ShortcutsAIService.shared.openShortcutsApp()
            }) {
                HStack {
                    Image(systemName: "square.on.square")
                    Text("Open Shortcuts App")
                }
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

        // Section 4: setup instructions
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
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text("Pro Tip")
                        .font(.caption)
                        .fontWeight(.semibold)
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
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("How It Works")
                        .font(.caption)
                        .fontWeight(.semibold)
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

    private func commitAddShortcut() {
        let name = newShortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        shortcuts.addShortcutName(name)
        newShortcutName = ""
        isAddingShortcut = false
    }

    private func instructionRow(number: Int, text: String) -> some View {
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
