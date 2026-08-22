//
//  MacBackgroundModeTests.swift
//  PodcastAnalyzerTests
//
//  The activation-policy rule. Worth a test because the failure it replaces
//  was silent and total: the app set .accessory during init on every launch,
//  so double-clicking it produced no dock icon, no menu bar and no window.
//
//  Only the rule is covered. Closing a window is not scriptable from a test
//  process, which is exactly why the decision was pulled out of the NSApp
//  plumbing and given its own function.
//

#if os(macOS)

import AppKit
import Testing
@testable import PodcastAnalyzer

@MainActor
@Suite("macOS background mode")
struct MacBackgroundModeTests {

    @Test("A window on screen always keeps the dock icon, headless or not")
    func visibleWindowStaysRegular() {
        #expect(MacBackgroundMode.policy(headless: true, hasVisibleWindow: true) == .regular)
        #expect(MacBackgroundMode.policy(headless: false, hasVisibleWindow: true) == .regular)
    }

    @Test("Headless drops to accessory only once nothing is on screen")
    func headlessGoesAccessoryWhenEmpty() {
        #expect(MacBackgroundMode.policy(headless: true, hasVisibleWindow: false) == .accessory)
    }

    @Test("Without headless the app stays a normal app even with no windows")
    func nonHeadlessNeverHides() {
        #expect(MacBackgroundMode.policy(headless: false, hasVisibleWindow: false) == .regular)
    }
}

#endif
