import XCTest

final class TaskDetailContextUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testParentContextIsReachableAtLargeTextAndReturnsWithoutNavigationLoops() {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": "task:Pay the ryokan deposit"])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.waitForScreen("screen.taskDetail", timeout: 45)
        waitForTitle("Pay the ryokan deposit", in: app)
        XCTAssertGreaterThan(app.textFields["detail.title"].frame.height, 60,
                             "The task title must actually render at accessibility XXXL")
        let parent = app.buttons["detail.parent"]
        reveal(parent, in: app)
        XCTAssertEqual(parent.label, "Subtask of Book the ryokan, 1 of 3 subtasks complete")
        XCTAssertGreaterThanOrEqual(parent.frame.height, 44)
        XCTAssertGreaterThanOrEqual(parent.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(parent.frame.maxX, app.frame.maxX)
        snapshot("detail-parent-xxxl")
        parent.tap()
        waitForTitle("Book the ryokan", in: app)
        XCTAssertFalse(app.buttons["detail.parent"].exists)

        let child = app.buttons["Pay the ryokan deposit"]
        reveal(child, in: app)
        child.tap()
        waitForTitle("Pay the ryokan deposit", in: app)
        reveal(parent, in: app)
        parent.tap()
        waitForTitle("Book the ryokan", in: app)
        let back = app.buttons["Back to Weekend in Kyoto"]
        reveal(back, in: app)
        back.tap()
        app.waitForScreen("screen.list")
        XCTAssertFalse(app.screen("screen.taskDetail").exists, "Returning to the parent must not leave duplicate child/parent pages behind it")
    }

    @MainActor
    func testArchivedTaskCanClearItsExistingTodaySelectionButCannotEnableItAgain() {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": "task:Start Piranesi"])
        app.launch()
        app.waitForScreen("screen.taskDetail", timeout: 45)
        let plan = app.switches["detail.plan"]
        reveal(plan, in: app)
        XCTAssertTrue(plan.isEnabled)
        XCTAssertEqual(plan.value as? String, "0")
        plan.tap()
        XCTAssertEqual(plan.value as? String, "1")

        relaunch(app, route: "lists", screen: "screen.lists")
        app.buttons["Reading"].firstMatch.press(forDuration: 1)
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.staticTexts["Archived “Reading”"].waitForExistence(timeout: 5))
        relaunch(app, route: "task:Start Piranesi", screen: "screen.taskDetail")
        reveal(plan, in: app)
        XCTAssertEqual(plan.value as? String, "1")
        XCTAssertTrue(plan.isEnabled, "An existing selection must remain removable after archiving its list")
        plan.tap()
        XCTAssertEqual(plan.value as? String, "0")
        XCTAssertFalse(plan.isEnabled, "Archived tasks cannot promise to appear in the active Today view")
        snapshot("detail-archived-today-disabled")

        relaunch(app, route: "task:Start Piranesi", screen: "screen.taskDetail")
        reveal(plan, in: app)
        XCTAssertEqual(plan.value as? String, "0")
        XCTAssertFalse(plan.isEnabled)
        XCTAssertTrue(app.buttons["detail.when"].label.contains("None"), "Changing Today membership preserves the due date")
    }

    @MainActor
    private func relaunch(_ app: XCUIApplication, route: String, screen: String) {
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launchEnvironment["OpenlistOpenRoute"] = route
        app.launch()
        app.waitForScreen(screen, timeout: 30)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        let top = app.statusBars.firstMatch.exists ? app.statusBars.firstMatch.frame.maxY : app.frame.minY
        for _ in 0..<16 {
            let dock = app.buttons["detail.start"]
            let bottom = dock.exists ? dock.frame.minY : app.frame.maxY
            if element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { return }
            guard element.exists, !element.frame.isEmpty else {
                app.swipeUp()
                continue
            }
            let distance = element.frame.minY < top
                ? min(280, max(80, top - element.frame.minY + 16))
                : -min(280, max(80, element.frame.maxY - bottom + 16))
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)))
        }
        XCTFail("The task detail control must be reachable above its action dock: \(element)")
    }

    @MainActor
    private func waitForTitle(_ title: String, in app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", title),
                                                   object: app.textFields["detail.title"])
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)
    }

    @MainActor
    private func snapshot(_ name: String) {
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
