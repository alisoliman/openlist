//
//  NavigationUITests.swift
//  OpenlistiOSUITests
//

import XCTest

/// Where things open and how they come back: Capture's draft outliving the
/// sheet, a task's history as a page, Working's own stack, Settings' sheet
/// and the place the system puts back after ending the app.
@MainActor
final class NavigationUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// A link that takes the screen from Capture keeps what was typed for
    /// the next Capture. The link comes through the system, as a widget's
    /// does, to the app still running. (The tray saying so drains while the
    /// link lands, so the test reopens Capture from the dock.)
    func testALinkKeepsTheCaptureDraft() throws {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": "inbox"])
        app.launch()
        app.waitForScreen("screen.inbox", timeout: 20)
        app.dock("capture").tap()
        app.waitForScreen("screen.capture")
        let field = app.textFields["capture.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Call the plumber")
        XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "openlist://widget/today")))
        let confirm = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        app.waitForScreenToClose("screen.capture")
        app.waitForScreen("screen.today")
        app.dock("capture").tap()
        app.waitForScreen("screen.capture")
        XCTAssertEqual(app.textFields["capture.field"].value as? String, "Call the plumber")
        app.discardCapture()
        app.dock("capture").tap()
        app.waitForScreen("screen.capture")
        XCTAssertNotEqual(app.textFields["capture.field"].value as? String, "Call the plumber")
    }

    /// Cancel with a draft asks; Keep for Later closes and the next Capture
    /// starts from the draft.
    func testCancelAsksAndCanKeepTheDraft() {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": "inbox"])
        app.launch()
        app.waitForScreen("screen.inbox", timeout: 20)
        app.dock("capture").tap()
        app.waitForScreen("screen.capture")
        let field = app.textFields["capture.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Renew the passport")
        app.screen("screen.capture").buttons["Cancel"].tap()
        let keep = app.buttons["Keep for Later"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Discard"].exists)
        keep.tap()
        app.waitForScreenToClose("screen.capture")
        XCTAssertFalse(app.buttons["Renew the passport"].exists, "Keeping a draft must not add it")
        app.dock("capture").tap()
        app.waitForScreen("screen.capture")
        XCTAssertEqual(app.textFields["capture.field"].value as? String, "Renew the passport")
        app.discardCapture()
    }

    /// A task's History is its own page, with all activity one step on, and
    /// Back walks the same way home.
    func testTaskHistoryIsAPage() {
        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)
        app.buttons["Write interview feedback for Priya"].tap()
        app.waitForScreen("screen.taskDetail")
        app.buttons["detail.history"].tap()
        app.waitForScreen("screen.taskHistory")
        app.buttons["history.activity"].tap()
        app.waitForScreen("screen.activity")
        app.buttons["Back to History"].tap()
        app.waitForScreen("screen.taskHistory")
        app.buttons["Back to Write interview feedback for Priya"].tap()
        app.waitForScreen("screen.taskDetail")
    }

    /// A task opened from Working pushes over the timer, and Back comes back
    /// to it rather than to the tab underneath.
    func testWorkingKeepsItsOwnStack() {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": "working"])
        app.launch()
        app.waitForScreen("screen.working", timeout: 20)
        app.buttons["Task details"].firstMatch.tap()
        app.waitForScreen("screen.taskDetail")
        app.buttons["Back to Working"].tap()
        app.waitForScreen("screen.working")
        app.buttons["working.close"].firstMatch.tap()
        app.waitForScreenToClose("screen.working")
        app.waitForScreen("screen.today")
    }

    /// Settings is a sheet with its own stack: Plan hours pushes inside it.
    func testPlanHoursPushesInsideSettings() {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": "settings"])
        app.launch()
        app.waitForScreen("screen.settings", timeout: 20)
        app.buttons["settings.planHours"].tap()
        app.waitForScreen("screen.planHours")
        app.buttons["Back to Settings"].tap()
        app.waitForScreen("screen.settings")
        app.buttons["settings.done"].tap()
        app.waitForScreenToClose("screen.settings")
    }

    /// The system ending the app in the background puts it back where it
    /// was: the tab and the page on its stack.
    func testThePlaceComesBackAfterTheSystemEndsTheApp() {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistRestoresPlace": "1"])
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)
        app.dock("lists").tap()
        app.waitForScreen("screen.lists")
        app.buttons["Weekend in Kyoto"].firstMatch.tap()
        app.waitForScreen("screen.list")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackgroundSuspended, timeout: 10) || app.state == .runningBackground)
        app.terminate()
        app.launch()
        app.waitForScreen("screen.list", timeout: 20)
        XCTAssertTrue(app.dock("lists").exists || app.buttons["Back to Lists"].exists)
    }
}
