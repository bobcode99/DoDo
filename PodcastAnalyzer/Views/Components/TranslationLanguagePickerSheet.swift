//
//  TranslationLanguagePickerSheet.swift
//  PodcastAnalyzer
//
//  Language picker sheet for selecting translation target language
//

import SwiftUI

struct TranslationLanguagePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Set of language codes that have cached translations available
    let availableTranslations: Set<String>

    /// The transcript's own language, never offered as a target
    let sourceLanguage: Locale.Language?

    /// Target of the transcript translation still in progress, if any
    let translatingLanguage: TranslationTargetLanguage?

    /// Callback when a language is selected
    let onSelectLanguage: (TranslationTargetLanguage) -> Void

    private var settings: SubtitleSettingsManager { .shared }

    var body: some View {
        NavigationStack {
            List {
                // Currently selected default language section
                if !settings.targetLanguage.isSameLanguage(as: sourceLanguage) {
                    Section {
                        Button {
                            onSelectLanguage(settings.targetLanguage)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Default Language")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(settings.targetLanguage.displayName)
                                        .font(.headline)
                                }

                                Spacer()

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Text("Quick Translate")
                    } footer: {
                        Text("Tap to translate to your default language. Change the default in Settings.")
                    }
                }

                // All available languages
                Section {
                    ForEach(Self.offeredLanguages(source: sourceLanguage), id: \.self) { language in
                        languageRow(for: language)
                    }
                } header: {
                    Text("All Languages")
                }
            }
            .navigationTitle("Translate To")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func languageRow(for language: TranslationTargetLanguage) -> some View {
        let langCode = language.languageIdentifier
        let hasTranslation = availableTranslations.contains(langCode)
        let isTranslatingThisLanguage = translatingLanguage == language

        Button {
            onSelectLanguage(language)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.displayName)
                        .foregroundStyle(.primary)

                    if hasTranslation {
                        Text("Cached")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                if isTranslatingThisLanguage {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Translating...")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                } else if hasTranslation {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .disabled(isTranslatingThisLanguage)
    }

    /// Every explicit target except the transcript's own language, since
    /// translating a show into the language it's already in does nothing.
    static func offeredLanguages(source: Locale.Language?) -> [TranslationTargetLanguage] {
        TranslationTargetLanguage.allCases.filter { $0 != .deviceLanguage && !$0.isSameLanguage(as: source) }
    }
}

#Preview {
    TranslationLanguagePickerSheet(
        availableTranslations: ["zh-Hant", "ja"],
        sourceLanguage: Locale.Language(identifier: "en"),
        translatingLanguage: .korean,
        onSelectLanguage: { _ in }
    )
}
