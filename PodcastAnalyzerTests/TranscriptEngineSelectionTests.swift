//
//  TranscriptEngineSelectionTests.swift
//  PodcastAnalyzerTests
//
//  The generate screen and the regenerate sheet both choose an engine and a
//  language through the coordinator, so the rules live in one place.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Transcript engine and language selection")
struct TranscriptEngineSelectionTests {

    private func coordinator(podcastLanguage: String = "en") -> TranscriptCoordinator {
        TranscriptCoordinator(
            episode: PodcastEpisodeInfo(title: "Episode"),
            podcastTitle: "Show",
            podcastLanguage: podcastLanguage
        )
    }

    @Test("Switching to Apple Speech drops a language only Whisper offers")
    func switchingDropsUnsupportedLanguage() {
        let transcript = coordinator()
        transcript.selectedTranscriptEngine = .whisper
        transcript.selectedTranscriptLanguage = "ur"
        transcript.selectEngine(.appleSpeech)
        #expect(transcript.selectedTranscriptEngine == .appleSpeech)
        #expect(transcript.selectedTranscriptLanguage == nil)
    }

    @Test("Switching engines keeps a language both support")
    func switchingKeepsSupportedLanguage() {
        let transcript = coordinator()
        transcript.selectedTranscriptEngine = .whisper
        transcript.selectedTranscriptLanguage = "en-us"
        transcript.selectEngine(.appleSpeech)
        #expect(transcript.selectedTranscriptLanguage == "en-us")
    }

    @Test("Whisper keeps whatever language was chosen")
    func whisperKeepsLanguage() {
        let transcript = coordinator()
        transcript.selectedTranscriptEngine = .appleSpeech
        transcript.selectedTranscriptLanguage = "en-us"
        transcript.selectEngine(.whisper)
        #expect(transcript.selectedTranscriptLanguage == "en-us")
    }

    @Test("The engine picker value goes through the same rule")
    func engineSelectionSetter() {
        let transcript = coordinator()
        transcript.selectedTranscriptEngine = .whisper
        transcript.selectedTranscriptLanguage = "ur"
        transcript.engineSelection = .yapServer
        #expect(transcript.engineSelection == .yapServer)
        #expect(transcript.selectedTranscriptLanguage == nil)
    }

    @Test("Apple Speech shows the podcast language mapped to its closest locale")
    func podcastLanguageIsResolved() {
        let transcript = coordinator(podcastLanguage: "en")
        transcript.selectedTranscriptEngine = .appleSpeech
        #expect(transcript.languagePickerSelection == "en-us")
    }

    @Test("An explicit language wins over the podcast language")
    func explicitLanguageWins() {
        let transcript = coordinator(podcastLanguage: "en")
        transcript.selectedTranscriptEngine = .appleSpeech
        transcript.languagePickerSelection = "fr-fr"
        #expect(transcript.selectedTranscriptLanguage == "fr-fr")
        #expect(transcript.languagePickerSelection == "fr-fr")
    }

    @Test("Whisper reads auto for no language, and choosing auto clears it")
    func whisperAuto() {
        let transcript = coordinator()
        transcript.selectedTranscriptEngine = .whisper
        #expect(transcript.languagePickerSelection == "auto")
        transcript.languagePickerSelection = "de-de"
        #expect(transcript.selectedTranscriptLanguage == "de-de")
        transcript.languagePickerSelection = "auto"
        #expect(transcript.selectedTranscriptLanguage == nil)
    }

    @Test("The picker adds the podcast's own language when the engine lacks it")
    func pickerAddsPodcastLanguage() {
        let transcript = coordinator(podcastLanguage: "nl")
        transcript.selectedTranscriptEngine = .appleSpeech
        #expect(transcript.pickerLocales.first?.id == "nl")
        #expect(transcript.pickerLocales.count == SettingsViewModel.locales(for: .appleSpeech).count + 1)
    }

    @Test("An empty podcast language adds nothing to the picker")
    func pickerIgnoresEmptyPodcastLanguage() {
        let transcript = coordinator(podcastLanguage: "")
        transcript.selectedTranscriptEngine = .appleSpeech
        #expect(transcript.pickerLocales.count == SettingsViewModel.locales(for: .appleSpeech).count)
    }
}
