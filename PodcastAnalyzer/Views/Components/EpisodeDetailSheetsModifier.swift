import SwiftUI

#if canImport(Translation)
@preconcurrency import Translation
import SwiftData
#endif

extension View {
    /// Bundles all the cross-platform episode-detail side effects: confirmation
    /// dialogs, sheets, translation-error alert, view-model lifecycle, and the
    /// four `translationTask` modifiers that drive on-device translation.
    func episodeDetailSheetsAndAlerts(
        viewModel: EpisodeDetailViewModel,
        showDeleteConfirmation: Binding<Bool>,
        showSubtitleSettings: Binding<Bool>,
        showRegenerateConfirmation: Binding<Bool>,
        showTranslationLanguagePicker: Binding<Bool>
    ) -> some View {
        modifier(
            EpisodeDetailSheetsModifier(
                viewModel: viewModel,
                showDeleteConfirmation: showDeleteConfirmation,
                showSubtitleSettings: showSubtitleSettings,
                showRegenerateConfirmation: showRegenerateConfirmation,
                showTranslationLanguagePicker: showTranslationLanguagePicker
            )
        )
    }
}

private struct EpisodeDetailSheetsModifier: ViewModifier {
    @Bindable var viewModel: EpisodeDetailViewModel
    @Binding var showDeleteConfirmation: Bool
    @Binding var showSubtitleSettings: Bool
    @Binding var showRegenerateConfirmation: Bool
    @Binding var showTranslationLanguagePicker: Bool

    @State private var showTranslationError = false
    @State private var translationErrorMessage = ""

    @State private var transcriptTranslationConfig: TranslationSession.Configuration?
    @State private var descriptionTranslationConfig: TranslationSession.Configuration?
    @State private var titleTranslationConfig: TranslationSession.Configuration?
    @State private var podcastTitleTranslationConfig: TranslationSession.Configuration?

    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content
            .alert("Translation Failed", isPresented: $showTranslationError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(translationErrorMessage)
            }
            .onChange(of: viewModel.translationStatus) { _, newStatus in
                if case .failed(let error) = newStatus {
                    translationErrorMessage = error
                    showTranslationError = true
                }
            }
            .confirmationDialog(
                "Delete Download",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteDownload()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this downloaded episode? You can download it again later.")
            }
            .sheet(isPresented: $showSubtitleSettings) {
                SubtitleSettingsSheet(hasTranslation: viewModel.hasExistingTranslation)
            }
            .sheet(isPresented: $showRegenerateConfirmation) {
                TranscriptRegenerateSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showTranslationLanguagePicker) {
                TranslationLanguagePickerSheet(
                    availableTranslations: viewModel.availableTranslationLanguages,
                    translationStatus: viewModel.translationStatus,
                    onSelectLanguage: { language in
                        viewModel.translateTo(language)
                    }
                )
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
                viewModel.checkTranscriptStatus()
                viewModel.loadExistingTranslations()
                viewModel.checkAvailableTranslations()
            }
            .onDisappear {
                viewModel.cleanup()
            }
            .onChange(of: viewModel.transcriptTranslationTrigger) { _, _ in
                triggerTranscriptTranslation()
            }
            .onChange(of: viewModel.descriptionTranslationTrigger) { _, _ in
                triggerDescriptionTranslation()
            }
            .onChange(of: viewModel.episodeTitleTranslationTrigger) { _, _ in
                triggerTitleTranslation()
            }
            .onChange(of: viewModel.podcastTitleTranslationTrigger) { _, _ in
                triggerPodcastTitleTranslation()
            }
            .translationTask(transcriptTranslationConfig) { session in
                await viewModel.performTranscriptTranslation(using: session)
            }
            .translationTask(descriptionTranslationConfig) { session in
                await viewModel.performDescriptionTranslation(using: session)
            }
            .translationTask(titleTranslationConfig) { session in
                await viewModel.performTitleTranslation(using: session)
            }
            .translationTask(podcastTitleTranslationConfig) { session in
                await viewModel.performPodcastTitleTranslation(using: session)
            }
    }

    // MARK: - Translation triggers

    private func triggerTranscriptTranslation() {
        guard let targetLang = viewModel.selectedTranslationLanguage?.localeLanguage else { return }
        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        transcriptTranslationConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
    }

    private func triggerDescriptionTranslation() {
        guard let targetLang = viewModel.selectedTranslationLanguage?.localeLanguage else { return }
        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        descriptionTranslationConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
    }

    private func triggerTitleTranslation() {
        guard let targetLang = viewModel.selectedTranslationLanguage?.localeLanguage else { return }
        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        titleTranslationConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
    }

    private func triggerPodcastTitleTranslation() {
        guard let targetLang = viewModel.selectedTranslationLanguage?.localeLanguage else { return }
        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        podcastTitleTranslationConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
    }
}
