//
//  ExpandedPlayerMenuSelectionTests.swift
//  PodcastAnalyzerTests
//
//  The speed and sleep timer menus are pickers bound to the view model, so the
//  view model has to report the current choice and apply a new one. Nested in
//  the serialized player suite: both choices live on `EnhancedAudioManager.shared`.
//

import Foundation
import Testing
@testable import PodcastAnalyzer

extension PlayerInteractionFlowTests {

@MainActor
@Suite("Expanded player menu selection")
struct ExpandedPlayerMenuSelection {

    @Test("The speed menu marks the preset the playback rate matches")
    func selectedSpeedFollowsRate() {
        let audio = EnhancedAudioManager.shared
        let previous = audio.playbackRate
        defer { audio.setPlaybackRate(previous) }
        let viewModel = ExpandedPlayerViewModel()

        viewModel.selectedSpeed = 1.5

        #expect(audio.playbackRate == 1.5)
        #expect(viewModel.selectedSpeed == 1.5)
    }

    @Test("A rate that is not a preset leaves the speed menu without a mark")
    func selectedSpeedIsNilOffPreset() {
        let audio = EnhancedAudioManager.shared
        let previous = audio.playbackRate
        defer { audio.setPlaybackRate(previous) }
        let viewModel = ExpandedPlayerViewModel()

        viewModel.setPlaybackSpeed(1.1)

        #expect(viewModel.selectedSpeed == nil)
    }

    @Test("Choosing a sleep timer in the menu starts it, and Off stops it")
    func sleepTimerSelectionRoundTrips() {
        let audio = EnhancedAudioManager.shared
        defer { audio.setSleepTimer(.off) }
        let viewModel = ExpandedPlayerViewModel()

        viewModel.sleepTimerOption = .minutes5
        #expect(audio.sleepTimerOption == .minutes5)
        #expect(viewModel.isSleepTimerActive)

        viewModel.sleepTimerOption = .off
        #expect(audio.sleepTimerOption == .off)
        #expect(!viewModel.isSleepTimerActive)
    }
}

}
