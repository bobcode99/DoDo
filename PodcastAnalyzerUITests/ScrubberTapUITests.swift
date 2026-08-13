//
//  ScrubberTapUITests.swift
//  PodcastAnalyzerUITests
//
//  The scrubber follows Apple Podcasts: you *grab* the bar and drag it. A bare
//  tap must NOT move the playhead — a full-width bar that seeks on touch means
//  any stray contact destroys your position, with no undo.
//
//  Both halves of that contract are asserted here, because they pull in
//  opposite directions and it is easy to "fix" one by breaking the other.
//

import XCTest

final class ScrubberTapUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testTapDoesNotMoveThePlayhead() throws {
        let app = launchIntoPlayer()
        let slider = try scrubber(in: app)
        let elapsedBefore = try XCTUnwrap(elapsedSeconds(in: app), "should show an elapsed time")

        // Land far from the current position, so a jump-to-touch regression
        // would show up as a large change rather than a rounding wobble.
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        sleep(3)

        attachScreenshot(app, named: "after-bare-tap")
        let elapsedAfter = try XCTUnwrap(elapsedSeconds(in: app), "should still show an elapsed time")

        // Allow a couple of seconds of drift in case playback is running.
        XCTAssertLessThanOrEqual(
            abs(elapsedAfter - elapsedBefore), 3,
            """
            A bare tap must not seek — the bar is grabbed and dragged, \
            Apple Podcasts style. Elapsed went \(elapsedBefore)s -> \(elapsedAfter)s.
            """
        )
    }

    func testDraggingScrubberSeeks() throws {
        let app = launchIntoPlayer()
        let slider = try scrubber(in: app)
        let elapsedBefore = try XCTUnwrap(elapsedSeconds(in: app), "should show an elapsed time")

        // Drag right from the middle. Relative, not absolute: the playhead is
        // picked up from where it sits and carried by the drag distance.
        let from = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to)
        sleep(3)

        attachScreenshot(app, named: "after-drag")
        let elapsedAfter = try XCTUnwrap(elapsedSeconds(in: app), "should still show an elapsed time")

        XCTAssertGreaterThan(
            abs(elapsedAfter - elapsedBefore), 30,
            "Dragging the bar must seek. Elapsed went \(elapsedBefore)s -> \(elapsedAfter)s."
        )
    }

    // MARK: - Helpers

    private func launchIntoPlayer() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        dismissSystemAlerts()

        let miniPlayer = app.buttons["MiniPlayerBar"].firstMatch
        if miniPlayer.waitForExistence(timeout: 5) {
            miniPlayer.tap()
        } else {
            // Fall back to the accessory strip above the tab bar.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.885)).tap()
        }
        return app
    }

    /// Matched by accessibility label, not element type: the scrubber is a
    /// SwiftUI view with an adjustable action, so it does not necessarily
    /// surface as `app.sliders` the way the old UISlider did.
    private func scrubber(in app: XCUIApplication) throws -> XCUIElement {
        let slider = app.descendants(matching: .any)
            .matching(identifier: "Playback position").firstMatch
        XCTAssertTrue(
            slider.waitForExistence(timeout: 10),
            "expanded player scrubber should be on screen"
        )
        return slider
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Elapsed time from the player's "m:ss" / "h:mm:ss" label. The remaining
    /// label is prefixed with "-", so it is filtered out.
    private func elapsedSeconds(in app: XCUIApplication) -> Int? {
        for element in app.staticTexts.allElementsBoundByIndex {
            let label = element.label
            guard !label.hasPrefix("-") else { continue }
            let parts = label.split(separator: ":")
            guard parts.count >= 2, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
                  let numbers = try? parts.map({ try XCTUnwrap(Int($0)) })
            else { continue }
            return numbers.reduce(0) { $0 * 60 + $1 }
        }
        return nil
    }

    private func dismissSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<3 {
            let dontAllow = springboard.buttons["Don't Allow"]
            let allow = springboard.buttons["Allow"]
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
