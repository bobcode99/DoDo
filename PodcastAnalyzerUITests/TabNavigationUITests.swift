//
//  TabNavigationUITests.swift
//  PodcastAnalyzerUITests
//
//  Drives the tab bar so SwiftUI's runtime navigation warnings can be observed
//  in the device log. "Update NavigationRequestObserver tried to update
//  multiple times per frame" is emitted only when a real switch happens on a
//  freshly launched app, which no unit test can reproduce.
//

import XCTest

final class TabNavigationUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Launch on Home, then switch to Library — the exact sequence that
    /// reproduces the navigation warning.
    func testHomeToLibrarySwitch() {
        let app = XCUIApplication()
        app.launch()

        // Permission alerts (Speech Recognition, notifications) can cover the
        // tab bar on a clean install; dismiss whatever is up.
        dismissSystemAlerts(in: app)

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "tab bar should exist")

        // Index, not label — the app runs localized (zh-Hant here), so
        // matching on "Library" only works in an English locale.
        let library = tabBar.buttons.element(boundBy: 1)
        XCTAssertTrue(library.waitForExistence(timeout: 20), "Library tab should exist")
        library.tap()

        // Give the transition a beat so any same-frame update warning is
        // emitted before the process is torn down.
        sleep(4)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "after-switching-to-library"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(library.isSelected, "Library tab should be the selected tab")
    }

    private func dismissSystemAlerts(in app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let allow = springboard.buttons["Allow"]
            let dontAllow = springboard.buttons["Don't Allow"]
            if dontAllow.waitForExistence(timeout: 3) {
                dontAllow.tap()
            } else if allow.exists {
                allow.tap()
            } else {
                break
            }
        }
    }
}
