//
//  AISettingsLanguageSection.swift
//  PodcastAnalyzer
//
//  "Analysis Language" section of AISettingsView.
//

import SwiftUI

struct AISettingsLanguageSection: View {
    @Bindable private var settings = AISettingsManager.shared

    var body: some View {
        Section {
            Picker("Response Language", selection: $settings.analysisLanguage) {
                Section("Behavior") {
                    ForEach(AnalysisLanguage.behaviorCases, id: \.self) { language in
                        languagePickerRow(language)
                    }
                }
                Section("Popular Languages") {
                    ForEach(AnalysisLanguage.popularLanguageCases, id: \.self) { language in
                        languagePickerRow(language)
                    }
                }
                Section("Custom") {
                    languagePickerRow(.custom)
                }
            }
            #if os(iOS)
            .pickerStyle(.navigationLink)
            #else
            .pickerStyle(.menu)
            #endif

            // Custom language entry field (only when Custom selected)
            if settings.analysisLanguage == .custom {
                HStack(spacing: 8) {
                    Text(AnalysisLanguage.custom.emoji)
                    TextField(
                        "Language name (e.g. Italian, Swahili)",
                        text: $settings.customAnalysisLanguageName
                    )
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    #endif
                    .submitLabel(.done)
                }
            }

            // Show current language preview with resolved language
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.analysisLanguage.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Show resolved language
                    Text(resolvedLanguageText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
            }
        } header: {
            Text("Analysis Language")
        } footer: {
            Text("Controls the language of AI-generated summaries, highlights, and other analysis results.")
        }
    }

    /// Row used by every section of the Response Language picker.
    @ViewBuilder
    private func languagePickerRow(_ language: AnalysisLanguage) -> some View {
        Label {
            Text(language.displayName)
        } icon: {
            Text(language.emoji)
        }
        .tag(language)
    }

    /// Computed property to show the resolved language based on the current setting
    private var resolvedLanguageText: String {
        switch settings.analysisLanguage {
        case .deviceLanguage:
            let preferredLanguage = Locale.preferredLanguages.first ?? "en"
            let languageName = Locale.current.localizedString(forLanguageCode: preferredLanguage) ?? "English"
            return "Will respond in: \(languageName)"
        case .matchPodcast:
            return "Will respond in: Same as podcast language"
        case .custom:
            let trimmed = settings.customAnalysisLanguageName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Will respond in: (no custom language set — no instruction sent)"
            }
            return "Will respond in: \(trimmed)"
        default:
            return "Will respond in: \(settings.analysisLanguage.rawValue)"
        }
    }
}
