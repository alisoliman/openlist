//
//  WidgetsUITests.swift
//  OpenlistiOSUITests
//

import XCTest

/// The widgets and the work Live Activity (mockup 05), outside the app: the
/// Dynamic Island while work runs, the Lock Screen presentation in
/// Notification Center, and the widget gallery's Openlist widgets. SpringBoard
/// is driven by what it shows, so each step is saved for review
/// (`OPENLIST_SHOTS_DIR`, as `ScreensUITests`).
final class WidgetsUITests: XCTestCase {
    @MainActor private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    override func setUp() {
        continueAfterFailure = true
    }

    /// On the system clock, as the Lock Screen's buttons stamp their taps:
    /// a pinned clock would find them from days ahead.
    @MainActor
    func testWorkLiveActivity() throws {
        let app = XCUIApplication.reviewSession(now: nil)
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)
        sleep(2)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        sleep(2)
        snap("island-compact")

        // Held, the island opens to the expanded presentation.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.028)).press(forDuration: 1.2)
        sleep(2)
        snap("island-expanded")
        let expandedPause = springboard.buttons["Pause"]
        XCTAssertTrue(expandedPause.waitForExistence(timeout: 3), "The expanded island has Pause")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        sleep(1)

        // Notification Center draws the Lock Screen presentation.
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.002))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75)))
        sleep(2)
        snap("lock-live-activity")
        XCTAssertTrue(springboard.buttons["Done"].waitForExistence(timeout: 3), "The Lock Screen activity has Done")

        // The first activity asks once whether Openlist may show them.
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) {
            allow.tap()
            sleep(1)
        }
        // Pause from the activity acts in the app, and the activity follows.
        springboard.buttons["Pause"].firstMatch.tap()
        XCTAssertTrue(springboard.buttons["Resume"].waitForExistence(timeout: 10), "Pause from the activity pauses the work")
        snap("lock-live-activity-paused")
        springboard.buttons["Resume"].firstMatch.tap()
        XCTAssertTrue(springboard.buttons["Pause"].waitForExistence(timeout: 10))
        // Done completes the task in the app, and the activity goes.
        springboard.buttons["Done"].firstMatch.tap()
        let ended = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                              object: springboard.buttons["Pause"])
        XCTAssertEqual(XCTWaiter().wait(for: [ended], timeout: 15), .completed, "Done from the activity ends it")
        snap("lock-live-activity-done")
        let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995))
        bottom.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        sleep(1)
    }

    /// The widget gallery's Openlist widgets, with the sample the gallery
    /// previews, and each added to the Home Screen.
    @MainActor
    func testWidgetGallery() throws {
        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        sleep(1)
        // An empty spot on the Home Screen: a long press starts editing.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).press(forDuration: 1.6)
        sleep(1)
        snap("home-editing")
        let edit = springboard.buttons["Edit"]
        if edit.waitForExistence(timeout: 3) {
            edit.tap()
            sleep(1)
            let add = springboard.buttons["Add Widget"].exists ? springboard.buttons["Add Widget"] : springboard.buttons["Add Widgets"]
            if add.waitForExistence(timeout: 3) { add.tap() }
        } else if springboard.buttons["Add Widget"].exists {
            springboard.buttons["Add Widget"].tap()
        }
        sleep(2)
        snap("gallery")
        let search = springboard.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Openlist")
            sleep(2)
            snap("gallery-search")
        }
        let openlist = springboard.cells.containing(NSPredicate(format: "label CONTAINS 'Openlist'")).firstMatch
        let openlistButton = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Openlist'")).firstMatch
        if openlist.waitForExistence(timeout: 5) { openlist.tap() } else if openlistButton.exists { openlistButton.tap() }
        // Previews draw a moment after each page settles.
        sleep(4)
        snap("gallery-openlist-1")
        // Each page of the gallery is one widget and size.
        for page in 2...3 {
            springboard.swipeLeft()
            sleep(4)
            snap("gallery-openlist-\(page)")
        }
    }

    /// The Lock Screen's Openlist widgets: the Today ring and Up next, from
    /// the Lock Screen's own gallery, reached from the cover sheet.
    @MainActor
    func testLockScreenWidgetGallery() throws {
        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 45)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        sleep(1)
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.002))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75)))
        sleep(2)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 1.6)
        sleep(2)
        snap("lock-customize")
        for title in ["Customize", "Lock Screen"] {
            let button = springboard.buttons[title]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                sleep(2)
                snap("lock-customize-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
            }
        }
        // The widget row under the clock ("Add widgets") opens the Lock Screen's gallery.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.785)).tap()
        sleep(2)
        snap("lock-gallery")
        let openlist = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Openlist'")).firstMatch
        let openlistCell = springboard.cells.containing(NSPredicate(format: "label CONTAINS 'Openlist'")).firstMatch
        if openlist.waitForExistence(timeout: 3) { openlist.tap() } else if openlistCell.exists { openlistCell.tap() } else {
            springboard.swipeUp()
            sleep(1)
            snap("lock-gallery-scrolled")
            let named = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == 'Openlist'"))
            let rows = named.allElementsBoundByIndex.filter { $0.frame.height > 0 && $0.frame.minY > 0 }
            print("Openlist rows:", rows.map { "\($0.elementType.rawValue) \($0.frame)" })
            if let row = rows.first {
                springboard.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: row.frame.midX, dy: row.frame.midY)).tap()
            }
        }
        sleep(2)
        snap("lock-gallery-openlist")
        // Each of Openlist's Lock Screen widgets, a page at a time: a drag
        // across the widget carousel in the sheet.
        for page in 2...3 {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.73))
                .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.73)))
            sleep(1)
            snap("lock-gallery-openlist-\(page)")
        }
    }

    // MARK: Helpers

    @MainActor
    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["OPENLIST_SHOTS_DIR"], !folder.isEmpty {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url)
        }
    }
}
