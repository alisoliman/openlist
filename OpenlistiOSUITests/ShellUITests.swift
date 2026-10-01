//
//  ShellUITests.swift
//  OpenlistiOSUITests
//

import XCTest

/// The shell every feature plugs into: the dock's tabs, Capture from the +,
/// and Settings from Lists.
final class ShellUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testTabsCaptureAndSettings() {
        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)

        XCTAssertEqual(app.dock("capture").label, "New task")
        app.dock("inbox").tap()
        app.waitForScreen("screen.inbox")
        XCTAssertTrue(app.dock("inbox").isSelected)
        // The design's label: the Inbox's own screen says how many.
        XCTAssertEqual(app.dock("inbox").label, "Inbox")
        XCTAssertFalse(app.dock("today").isSelected)

        app.dock("lists").tap()
        app.waitForScreen("screen.lists")

        app.dock("today").tap()
        app.waitForScreen("screen.today")

        app.dock("capture").tap()
        app.waitForScreen("screen.capture")
        app.buttons["Cancel"].tap()
        app.waitForScreenToClose("screen.capture")

        app.dock("lists").tap()
        app.waitForScreen("screen.lists")
        app.buttons["lists.settings"].tap()
        app.waitForScreen("screen.settings")
        app.buttons["Trash"].tap()
        app.waitForScreen("screen.trash")
        app.buttons["Back to Settings"].tap()
        app.waitForScreen("screen.settings")
        app.buttons["settings.done"].tap()
        app.waitForScreenToClose("screen.settings")
        app.waitForScreen("screen.lists")
    }

    /// Typing on a screen with the dock, such as Find, puts the dock behind
    /// the keyboard, as a tab bar goes, and the tray above the keyboard; the
    /// dock is back once the keyboard goes.
    @MainActor
    func testTheDockGoesBehindTheKeyboard() throws {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": "find:",
                                                              "OpenlistShowTray": "Restored to Home"])
        app.launch()
        app.waitForScreen("screen.find", timeout: 20)
        let tray = app.screen("tray")
        XCTAssertTrue(tray.waitForExistence(timeout: 5))
        app.textFields.firstMatch.tap()
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            throw XCTSkip("A hardware keyboard is connected, so the software keyboard never shows")
        }
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.dock("capture"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "The dock stayed with the keyboard up")
        XCTAssertLessThanOrEqual(tray.frame.maxY, keyboard.frame.minY + 1, "The tray went behind the keyboard")
        app.buttons["Back to Lists"].tap()
        app.waitForScreen("screen.lists")
        XCTAssertTrue(app.dock("capture").waitForExistence(timeout: 5))
    }

    /// A list's page names it on the + and pushes Task detail, which hides the dock.
    @MainActor
    func testListPageAndTaskDetail() {
        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)
        app.dock("lists").tap()
        app.waitForScreen("screen.lists")
        app.buttons["Weekend in Kyoto"].firstMatch.tap()
        app.waitForScreen("screen.list")
        XCTAssertEqual(app.dock("capture").label, "New task in Weekend in Kyoto")
        app.buttons["Back to Lists"].tap()
        app.waitForScreen("screen.lists")

        // The design's top bar hides the navigation bar; the edge swipe still goes back.
        app.buttons["Weekend in Kyoto"].firstMatch.tap()
        app.waitForScreen("screen.list")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 2, dy: 0))
        edge.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)),
                   withVelocity: XCUIGestureVelocity(rawValue: 1200), thenHoldForDuration: 0)
        app.waitForScreen("screen.lists")

        app.dock("today").tap()
        app.buttons["Close out Q2 retro actions"].tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertFalse(app.dock("today").exists)
        app.buttons["Back to Today"].tap()
        app.waitForScreen("screen.today")
        XCTAssertTrue(app.dock("today").exists)
    }
}
