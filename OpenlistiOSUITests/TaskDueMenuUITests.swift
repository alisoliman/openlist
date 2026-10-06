//
//  TaskDueMenuUITests.swift
//  OpenlistiOSUITests
//

import XCTest

/// A row's date is its own target: it offers other days in place, while the
/// rest of the row still opens the task.
final class TaskDueMenuUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testListRowDateMovesTheTaskWithoutOpeningIt() {
        let app = launch("list:Weekend in Kyoto", screen: "list")
        let title = "Renew passports"
        let due = app.buttons["task.due.\(title)"]
        reveal(due, in: app)
        XCTAssertEqual(due.label, "Due date")
        XCTAssertEqual(due.value as? String, "Sat")
        XCTAssertGreaterThanOrEqual(due.frame.height, 44)
        snapshot(app, "due-menu-list-before")

        due.tap()
        let tomorrow = app.buttons["Tomorrow"]
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 5), "The date offers other days")
        XCTAssertTrue(app.buttons["Next week"].exists)
        XCTAssertTrue(app.buttons["Due date…"].exists)
        XCTAssertTrue(app.buttons["Clear due date"].exists)
        snapshot(app, "due-menu-list-open")
        tomorrow.tap()
        XCTAssertTrue(app.screen("tray").staticTexts["“\(title)” due tomorrow"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.screen("screen.taskDetail").exists, "Changing the date does not open the task")
        XCTAssertEqual(due.value as? String, "Tomorrow")
        snapshot(app, "due-menu-list-moved")

        // A day from the picker, then Undo from the tray.
        due.tap()
        app.buttons["Due date…"].tap()
        let clear = app.buttons["Clear date"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "Due date… opens the date picker")
        snapshot(app, "due-menu-list-picker")
        clear.tap()
        XCTAssertTrue(app.screen("tray").staticTexts["Cleared the date of “\(title)”"].waitForExistence(timeout: 5))
        XCTAssertFalse(due.exists, "A task without a date has no date to change")
        app.buttons["tray.action"].tap()
        XCTAssertTrue(due.waitForExistence(timeout: 5))
        XCTAssertEqual(due.value as? String, "Tomorrow", "Undo restores the date it had")

        // On the title: XCUITest's own tap point for a row whose date came back
        // in place falls on the edge of the date's target.
        app.buttons[title].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertTrue(app.buttons["detail.when"].label.contains("Tomorrow"), "The rest of the row still opens the task")
    }

    @MainActor
    func testInboxRowDateMovesTheCaptureInPlace() {
        let app = launch("inbox", screen: "inbox")
        let title = "Return the library books"
        XCTAssertFalse(app.buttons["task.due.\(title)"].exists, "A capture's age is not a date to change")
        app.buttons[title].tap()
        app.waitForScreen("screen.taskDetail")
        app.buttons["detail.when"].tap()
        app.buttons["Tomorrow"].tap()
        app.buttons["Back to Inbox"].tap()
        app.waitForScreen("screen.inbox")

        let due = app.buttons["task.due.\(title)"]
        reveal(due, in: app)
        XCTAssertEqual(due.value as? String, "Tomorrow")
        due.tap()
        // The dock has a Today of its own; Next week is only the menu's.
        let nextWeek = app.buttons["Next week"]
        XCTAssertTrue(nextWeek.waitForExistence(timeout: 5))
        snapshot(app, "due-menu-inbox-open")
        nextWeek.tap()
        let moved = app.screen("tray").staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "“\(title)” due ")).firstMatch
        XCTAssertTrue(moved.waitForExistence(timeout: 5))
        XCTAssertFalse(app.screen("screen.taskDetail").exists, "Changing the date does not open the task")
        XCTAssertNotEqual(due.value as? String, "Tomorrow")
        snapshot(app, "due-menu-inbox-moved")
    }

    @MainActor
    private func launch(_ route: String, screen: String) -> XCUIApplication {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": route])
        app.launch()
        app.waitForScreen("screen.\(screen)", timeout: 45)
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing \(element)")
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let shot = app.screenshot()
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
