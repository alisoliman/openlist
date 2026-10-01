//
//  TaskSwipeUITests.swift
//  OpenlistiOSUITests
//

import XCTest

/// Exercises the actual drags and saved results, so gesture recognition,
/// row buttons, undo and the settings chosen by a person are tested together.
final class TaskSwipeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLongRightAddsTodayWithoutChangingDueDateAndSurvivesRelaunch() {
        let app = launch("list:Reading")
        let title = "Start Piranesi"
        drag(row(title, in: app), from: 0.22, to: 0.96)
        XCTAssertTrue(app.staticTexts["Added “Start Piranesi” to Today"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tray.action"].exists)
        app.buttons[title].tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertEqual(app.switches["detail.plan"].value as? String, "1")
        XCTAssertTrue(app.buttons["detail.when"].label.contains("None"), "Planning a task must preserve its due date")
        snapshot(app, "swipe-long-right-planned")
        app.buttons["Back to Reading"].tap()
        app.waitForScreen("screen.list")
        drag(row(title, in: app), from: 0.22, to: 0.96)
        app.buttons[title].tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertEqual(app.switches["detail.plan"].value as? String, "1", "A second long swipe keeps the task in Today")

        app.terminate()
        app.launchEnvironment["OpenlistOpenRoute"] = "today"
        app.launch()
        app.waitForScreen("screen.today", timeout: 30)
        reveal(app.buttons[title], in: app)
        XCTAssertTrue(app.buttons[title].isHittable, "The task added by a long swipe belongs in Today after relaunch")
        snapshot(app, "swipe-long-right-today-planned-group")
        app.buttons[title].tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertEqual(app.switches["detail.plan"].value as? String, "1")
    }

    @MainActor
    func testShortRightRevealsTwoActionsAndStarCanBeUndone() {
        let app = launch("list:Reading")
        let title = "Start Piranesi"
        let task = row(title, in: app)
        revealActions(task)
        let first = task.buttons["task.swipe.first"]
        let second = task.buttons["task.swipe.second"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        XCTAssertEqual(first.label, "Move to list")
        XCTAssertEqual(second.label, "Star")
        XCTAssertFalse(task.buttons["task.swipe.delete"].exists)
        snapshot(app, "swipe-short-right-actions")
        // The dock's SF Symbol exports identifier "tray" too. Every task
        // mutation offers this distinct Undo control; revealing choices does not.
        XCTAssertFalse(app.buttons["tray.action"].exists, "Revealing choices must not create an undoable mutation")
        task.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.5)).tap()
        XCTAssertFalse(first.exists, "Tapping the shifted row closes its revealed actions")
        XCTAssertFalse(app.screen("screen.taskDetail").exists, "Closing the actions does not also open the task")
        XCTAssertTrue(app.buttons["Complete Start Piranesi"].exists, "Closing the actions does not complete the task")
        revealActions(task)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.tap()
        XCTAssertTrue(app.screen("tray").staticTexts["Starred “Start Piranesi”"].waitForExistence(timeout: 5))
        app.buttons["tray.action"].tap()
        app.buttons[title].tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertEqual(app.buttons["detail.star"].label, "Star")
        XCTAssertEqual(app.switches["detail.plan"].value as? String, "0", "Revealing actions must not add the task to Today")
    }

    @MainActor
    func testShortRightMoveFilesInboxTaskAndUndoRestoresIt() {
        let app = launch("inbox")
        let title = "Send Jun the photos from Nara"
        let task = row(title, in: app)
        revealActions(task)
        task.buttons["task.swipe.first"].tap()
        let home = app.buttons.matching(NSPredicate(format: "label == 'Home' OR label == '🏡 Home'")).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        home.tap()
        XCTAssertTrue(app.screen("tray").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[title].exists, "Moving the capture files it out of Inbox")
        snapshot(app, "swipe-moved-from-inbox")
        app.buttons["tray.action"].tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5), "Undo restores the original Inbox membership")
    }

    @MainActor
    func testBothProgrammableActionsPersistAndExecuteTheirNewChoices() {
        let app = launch("settings")
        let first = app.buttons["settings.swipe.first"]
        reveal(first, in: app)
        first.tap()
        app.buttons["Tomorrow"].tap()
        let second = app.buttons["settings.swipe.second"]
        reveal(second, in: app)
        second.tap()
        app.buttons["Complete"].tap()
        snapshot(app, "swipe-settings-configured")

        app.terminate()
        app.launch()
        app.waitForScreen("screen.settings", timeout: 30)
        reveal(app.buttons["settings.swipe.first"], in: app)
        XCTAssertTrue(app.buttons["settings.swipe.first"].label.contains("Tomorrow"))
        XCTAssertTrue(app.buttons["settings.swipe.second"].label.contains("Complete"))
        app.terminate()
        app.launchEnvironment["OpenlistOpenRoute"] = "list:Reading"
        app.launch()
        app.waitForScreen("screen.list", timeout: 30)
        let title = "Start Piranesi"
        let task = row(title, in: app)
        revealActions(task)
        XCTAssertEqual(task.buttons["task.swipe.first"].label, "Tomorrow")
        XCTAssertEqual(task.buttons["task.swipe.second"].label, "Complete")
        task.buttons["task.swipe.first"].tap()
        XCTAssertTrue(app.screen("tray").waitForExistence(timeout: 5))
        app.buttons[title].tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertTrue(app.buttons["detail.when"].label.contains("Tomorrow"))
        app.buttons["Back to Reading"].tap()
        app.waitForScreen("screen.list")
        revealActions(task)
        task.buttons["task.swipe.second"].tap()
        XCTAssertTrue(app.screen("tray").staticTexts["Completed “Start Piranesi”"].waitForExistence(timeout: 5))
        app.buttons["tray.action"].tap()
        XCTAssertTrue(app.buttons["Complete Start Piranesi"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testShortLeftDeleteHasUndoAndLongLeftPersistsInTrash() {
        let app = launch("list:Reading")
        let title = "Start Piranesi"
        let task = row(title, in: app)
        let start = task.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -94, dy: 0)))
        let delete = task.buttons["task.swipe.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        snapshot(app, "swipe-left-delete")
        delete.tap()
        XCTAssertTrue(app.screen("tray").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[title].exists)
        app.buttons["tray.action"].tap()
        XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5))

        drag(task, from: 0.88, to: 0.06)
        XCTAssertTrue(app.screen("tray").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[title].exists)
        app.terminate()
        app.launchEnvironment["OpenlistOpenRoute"] = "trash"
        app.launch()
        app.waitForScreen("screen.trash", timeout: 30)
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "Left swipe moves the task to recoverable Trash")
        snapshot(app, "swipe-deleted-in-trash")
    }

    @MainActor
    func testLongRightOnAnArchivedListDoesNotPretendToAddToday() {
        let app = launch("lists")
        app.buttons["Reading"].firstMatch.press(forDuration: 1)
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.staticTexts["Archived “Reading”"].waitForExistence(timeout: 5))

        // Reopening the saved archived list also clears the archive's Undo
        // message, so any new action below has its own observable feedback.
        app.terminate()
        app.launchEnvironment["OpenlistOpenRoute"] = "list:Reading"
        app.launch()
        app.waitForScreen("screen.list", timeout: 30)
        let title = "Start Piranesi"
        let task = row(title, in: app)
        drag(task, from: 0.22, to: 0.96)
        XCTAssertTrue(task.buttons["task.swipe.first"].waitForExistence(timeout: 5))
        XCTAssertTrue(task.buttons["task.swipe.second"].exists)
        snapshot(app, "swipe-archived-list-shortcuts")
        XCTAssertFalse(app.buttons["tray.action"].exists, "An archived task cannot be added to the active Today view")
        task.buttons["task.swipe.close"].tap()
        let closeGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                  object: task.buttons["task.swipe.close"])
        let shortcutsGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                      object: task.buttons["task.swipe.first"])
        let closed = XCTWaiter().wait(for: [closeGone, shortcutsGone], timeout: 5)
        snapshot(app, "swipe-archived-after-close")
        XCTAssertEqual(closed, .completed, "Closing the archived row must dismiss its overlay and shortcuts.\n\(app.debugDescription)")
        XCTAssertFalse(app.screen("screen.taskDetail").exists, "Closing the actions does not also open the task")
        XCTAssertTrue(app.buttons["Complete Start Piranesi"].exists, "Closing the actions does not complete the task")
        app.buttons[title].tap()
        let detailOpened = app.screen("screen.taskDetail").waitForExistence(timeout: 10)
        snapshot(app, "swipe-archived-after-detail-tap")
        if !detailOpened {
            let hierarchy = app.debugDescription
            let attachment = XCTAttachment(string: hierarchy)
            attachment.name = "swipe-archived-missing-detail-hierarchy"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("The archived task detail did not open after the actions closed.\n\(hierarchy)")
        }
        XCTAssertEqual(app.switches["detail.plan"].value as? String, "0")
        XCTAssertTrue(app.buttons["detail.when"].label.contains("None"))
    }

    @MainActor
    func testConfiguredStartWorkingOpensTheSelectedTaskAndCanPause() {
        let app = launch("settings")
        let first = app.buttons["settings.swipe.first"]
        reveal(first, in: app)
        first.tap()
        app.buttons["Start working"].tap()
        app.terminate()
        app.launchEnvironment["OpenlistOpenRoute"] = "list:Reading"
        app.launch()
        app.waitForScreen("screen.list", timeout: 30)
        let task = row("Start Piranesi", in: app)
        revealActions(task)
        XCTAssertEqual(task.buttons["task.swipe.first"].label, "Start working")
        task.buttons["task.swipe.first"].tap()
        app.waitForScreen("screen.working")
        XCTAssertTrue(app.staticTexts["Start Piranesi"].waitForExistence(timeout: 5))
        let pause = app.buttons["working.pause"]
        XCTAssertEqual(pause.label, "Pause")
        XCTAssertTrue(pause.isHittable)
        snapshot(app, "swipe-configured-start-working")
        pause.tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["working.pause"].label, "Resume")
    }

    @MainActor
    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": route])
        app.launch()
        let screen = route.hasPrefix("list:") ? "list" : route
        app.waitForScreen("screen.\(screen)", timeout: 45)
        return app
    }

    @MainActor
    private func row(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let element = app.screen("task.swipe.\(title)")
        XCTAssertTrue(element.waitForExistence(timeout: 10), "Missing swipe row for \(title)")
        return element
    }

    @MainActor
    private func revealActions(_ row: XCUIElement) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 94, dy: 0)))
    }

    @MainActor
    private func drag(_ row: XCUIElement, from: CGFloat, to: CGFloat) {
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
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
