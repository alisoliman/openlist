import XCTest

final class TaskHierarchyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testTodayShowsSubtasksOnceUnderTheirParentAcrossDateGroups() {
        let app = XCUIApplication.reviewSession()
        app.launch()
        let today = app.waitForScreen("screen.today", timeout: 45)
        XCTAssertEqual(app.screen("today.progress").value as? String, "2 of 13 done")

        let parent = today.buttons["Book the ryokan"]
        let undated = today.buttons["Email Kasuga about the tatami room"]
        let depositRows = today.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Pay the ryokan deposit"))
        let deposit = depositRows.firstMatch
        reveal(deposit, in: app)
        XCTAssertTrue(parent.exists)
        XCTAssertTrue(undated.exists)
        XCTAssertEqual(depositRows.count, 1, "A task due tonight also belongs to the visible starred parent's outline")
        XCTAssertLessThan(parent.frame.minY, undated.frame.minY)
        XCTAssertLessThan(undated.frame.minY, deposit.frame.minY)
        XCTAssertGreaterThan(undated.frame.minX, parent.frame.minX)
        XCTAssertGreaterThan(deposit.frame.minX, parent.frame.minX)
        snapshot(app, "today-subtasks")

        deposit.tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertEqual(app.textFields["detail.title"].value as? String, "Pay the ryokan deposit")
    }

    @MainActor
    func testInboxExpandsSubtasksWithoutAddingToTriageCount() {
        let parentTitle = "Send Jun the photos from Nara"
        let childTitle = "Pick the best photos"
        let app = XCUIApplication.reviewSession(environment: [
            "OpenlistInboxHierarchyFixture": "1",
            "OpenlistOpenRoute": "inbox",
        ])
        app.launch()
        let inbox = app.waitForScreen("screen.inbox", timeout: 45)
        let parent = inbox.buttons[parentTitle]
        let disclosure = inbox.buttons["Subtasks of \(parentTitle)"]
        let child = inbox.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", childTitle)).firstMatch
        let completed = inbox.buttons["Reopen Find the Nara album"]
        reveal(disclosure, in: app)
        XCTAssertEqual(disclosure.value as? String, "Collapsed, 1 of 2 done")
        XCTAssertFalse(child.exists, "Inbox starts with each capture collapsed")
        XCTAssertFalse(completed.exists)
        disclosure.tap()
        reveal(child, in: app)
        XCTAssertEqual(disclosure.value as? String, "Expanded, 1 of 2 done")
        XCTAssertTrue(completed.exists)
        XCTAssertGreaterThan(child.frame.minX, parent.frame.minX)
        XCTAssertGreaterThan(child.frame.minY, parent.frame.minY)
        XCTAssertTrue(inbox.staticTexts["6 to triage"].exists)
        snapshot(app, "inbox-expanded-subtasks")
        disclosure.tap()
        XCTAssertTrue(child.waitForNonExistence(timeout: 5))
        disclosure.tap()
        reveal(child, in: app)
        child.tap()

        app.waitForScreen("screen.taskDetail")
        XCTAssertEqual(app.textFields["detail.title"].value as? String, childTitle)
        XCTAssertTrue(app.buttons["detail.parent"].label.contains(parentTitle))
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let dock = app.dock("capture").frame.minY
        for _ in 0..<6 {
            if element.exists, element.isHittable, element.frame.maxY <= dock { return }
            app.swipeUp()
        }
        XCTFail("The task row must be reachable above the dock: \(element)")
    }
}
