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
            .onChange(of: viewModel.translation.translationStatus) { _, newStatus in
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
                SubtitleSettingsSheet(hasTranslation: viewModel.translation.hasExistingTranslation)
            }
            .sheet(isPresented: $showRegenerateConfirmation) {
                TranscriptRegenerateSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showTranslationLanguagePicker) {
                TranslationLanguagePickerSheet(
                    availableTranslations: viewModel.translation.availableTranslationLanguages,
                    translationStatus: viewModel.translation.translationStatus,
                    onSelectLanguage: { language in
                        viewModel.translation.translateTo(language)
                    }
                )
            }
            .onAppear {
                viewModel.setModelContext(modelContext)
                viewModel.transcript.checkTranscriptStatus()
                viewModel.translation.loadExistingTranslations()
                viewModel.translation.checkAvailableTranslations()
            }
            .onDisappear {
                viewModel.cleanup()
            }
            .onChange(of: viewModel.translation.transcriptTranslationTrigger) { _, _ in
                triggerTranscriptTranslation()
            }
            .onChange(of: viewModel.translation.descriptionTranslationTrigger) { _, _ in
                triggerDescriptionTranslation()
            }
            .onChange(of: viewModel.translation.episodeTitleTranslationTrigger) { _, _ in
                triggerTitleTranslation()
            }
            .onChange(of: viewModel.translation.podcastTitleTranslationTrigger) { _, _ in
                triggerPodcastTitleTranslation()
            }
            .translationTask(transcriptTranslationConfig) { session in
                await viewModel.translation.performTranscriptTranslation(using: session)
            }
            .translationTask(descriptionTranslationConfig) { session in
                await viewModel.translation.performDescriptionTranslation(using: session)
            }
            .translationTask(titleTranslationConfig) { session in
                await viewModel.translation.performTitleTranslation(using: session)
            }
            .translationTask(podcastTitleTranslationConfig) { session in
                await viewModel.translation.performPodcastTitleTranslation(using: session)
            }
    }

    // MARK: - Translation triggers

    /// `TranslationSession.Configuration` is Equatable, so re-assigning an
    /// equal value leaves `.translationTask` untouched and no session starts —
    /// re-translating to the same language would silently do nothing. Apple's
    /// contract for that case is `invalidate()`, which restarts the session.
    private func refreshConfig(_ config: inout TranslationSession.Configuration?) {
        guard let targetLang = viewModel.translation.selectedTranslationLanguage?.localeLanguage else { return }
        let sourceLang = TranslationService.shared.detectSourceLanguage(from: viewModel.podcastLanguage)
        let newConfig = TranslationService.shared.makeConfiguration(
            sourceLanguage: sourceLang,
            targetLanguage: targetLang
        )
        if config == newConfig {
            config?.invalidate()
        } else {
            config = newConfig
        }
    }

    private func triggerTranscriptTranslation() {
        refreshConfig(&transcriptTranslationConfig)
    }

    private func triggerDescriptionTranslation() {
        refreshConfig(&descriptionTranslationConfig)
    }

    private func triggerTitleTranslation() {
        refreshConfig(&titleTranslationConfig)
    }

    private func triggerPodcastTitleTranslation() {
        refreshConfig(&podcastTitleTranslationConfig)
    }
}
