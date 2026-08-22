//
//  TranscriptGenerateConfigPreviewTests.swift
//  PodcastAnalyzerTests
//
//  A #Preview compiles whether or not it can render — the failure shows up as a
//  crash in the canvas, which CI never sees. These build the same view model the
//  previews build and assert the state each one is meant to demonstrate, so a
//  change that breaks the canvas fails here first.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("Transcript config previews")
struct TranscriptGenerateConfigPreviewTests {

    private func makeViewModel(engine: TranscriptEngine?) -> EpisodeDetailViewModel {
        let episode = PodcastEpisodeInfo(
            title: "Understanding Swift Concurrency",
            podcastEpisodeDescription: "A deep dive into async/await.",
            pubDate: Date(),
            audioURL: "https://example.com/episode.mp3",
            duration: 1800
        )
        let viewModel = EpisodeDetailViewModel(
            episode: episode,
            podcastTitle: "The Swift Podcast",
            fallbackImageURL: nil,
            podcastLanguage: "en"
        )
        viewModel.transcript.selectedTranscriptEngine = engine
        return viewModel
    }

    @Test("Constructing the preview view model doesn't trap")
    func viewModelConstructs() {
        let viewModel = makeViewModel(engine: .appleSpeech)
        #expect(viewModel.podcastTitle == "The Swift Podcast")
        #expect(viewModel.transcript.effectiveEngine == .appleSpeech)
    }

    @Test("The download-required preview really is in that state")
    func downloadRequiredState() {
        let viewModel = makeViewModel(engine: .appleSpeech)
        // No local audio and a local engine, so the view shows the download prompt.
        #expect(!viewModel.hasLocalAudio)
        #expect(viewModel.transcript.effectiveEngine != .yapServer)
    }

    @Test("The ready-to-generate preview really is in that state")
    func readyToGenerateState() {
        let viewModel = makeViewModel(engine: .yapServer)
        // Yap streams the episode, so generation is offered without a download —
        // the only lever that reaches this state without a real audio file.
        #expect(viewModel.transcript.effectiveEngine == .yapServer)
    }

    @Test("Whisper offers the Auto-detect option the picker tags")
    func whisperAutoDetect() {
        let viewModel = makeViewModel(engine: .whisper)
        #expect(viewModel.transcript.effectiveEngine == .whisper)
        // nil language is what the binding reports as "auto".
        #expect(viewModel.transcript.selectedTranscriptLanguage == nil)
    }
}
