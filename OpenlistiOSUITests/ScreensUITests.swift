//
//  ScreensUITests.swift
//  OpenlistiOSUITests
//

import XCTest

/// Each screen of the iPhone mockups, walked through what it does: ticking
/// with Undo, Working's controls, Capture, triage, Select, Task detail, Find,
/// Activity, Settings and Trash. With `OPENLIST_SHOTS_DIR` in the runner's
/// environment (`TEST_RUNNER_OPENLIST_SHOTS_DIR` through xcodebuild), each
/// step's screen is saved there for review against the mockups.
final class ScreensUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Today

    /// A tick dwells with Undo in the tray; Undo takes it back.
    @MainActor
    func testTodayTickAndUndo() {
        let app = launch()
        let tick = app.buttons["Complete Fix the dripping bathroom tap"]
        XCTAssertTrue(tick.waitForExistence(timeout: 5))
        tick.tap()
        let tray = app.screen("tray")
        XCTAssertTrue(tray.waitForExistence(timeout: 5))
        XCTAssertTrue(tray.staticTexts["Completed “Fix the dripping bathroom tap”"].exists)
        snap(app, "today-tray")
        app.buttons["tray.action"].tap()
        XCTAssertTrue(app.buttons["Complete Fix the dripping bathroom tap"].waitForExistence(timeout: 5))
    }

    /// Everything done leaves Today clear, with a look at tomorrow.
    @MainActor
    func testTodayClears() {
        let app = launch(environment: ["OpenlistOpenRoute": "working"])
        app.waitForScreen("screen.working", timeout: 20)
        app.buttons["working.done"].tap()
        app.waitForScreenToClose("screen.working")
        app.waitForScreen("screen.today")
        let open = NSPredicate(format: "label BEGINSWITH 'Complete '")
        var ticked = 0
        while app.buttons.matching(open).count > 0, ticked < 20 {
            app.buttons.matching(open).firstMatch.tap()
            ticked += 1
        }
        XCTAssertTrue(app.staticTexts["Today is clear"].waitForExistence(timeout: 15))
        snap(app, "today-clear")
        app.buttons["Look at tomorrow"].tap()
        app.waitForScreen("screen.timeline")
        XCTAssertTrue(app.staticTexts["Tomorrow"].waitForExistence(timeout: 5))
    }

    // MARK: Timeline

    @MainActor
    func testTimelineDaysAndPlanning() {
        let app = launch()
        app.buttons["today.timeline"].tap()
        app.waitForScreen("screen.timeline")
        XCTAssertTrue(app.element(beginningWith: "Draft Q3 OKRs, Now ·").exists)
        XCTAssertTrue(app.element(beginningWith: "Design sync, Calendar event").exists)
        snap(app, "timeline")
        app.buttons["timeline.toPlan"].tap()
        XCTAssertTrue(app.screen("tray").waitForExistence(timeout: 5))
        snap(app, "timeline-planned")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Friday'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Fri"].waitForExistence(timeout: 5))
        app.buttons["timeline.list"].tap()
        app.waitForScreen("screen.today")
    }

    /// A task to plan, held and dropped on the timeline, lands at the time
    /// under the finger; a planned block moves the same way.
    @MainActor
    func testTimelineDragToPlan() {
        let app = launch()
        app.buttons["today.timeline"].tap()
        app.waitForScreen("screen.timeline")
        let card = app.descendants(matching: .any)["timeline.card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        snap(app, "timeline-day")
        // The row's first chip, the most late task, in view at the row's start.
        let chip = app.buttons.matching(identifier: "plan.chip").firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        let title = chip.label.components(separatedBy: ", ").dropLast().joined(separator: ", ")
        XCTAssertEqual(title, "Close out Q2 retro actions")
        chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.2, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.75)),
                   withVelocity: .slow, thenHoldForDuration: 1.0)
        XCTAssertTrue(app.screen("tray").staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Planned “\(title)” · Today"))
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(identifier: "plan.chip").matching(NSPredicate(format: "label BEGINSWITH %@", title))
            .firstMatch.exists, "A planned task leaves the row")
        snap(app, "timeline-dropped")
        let block = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Write interview feedback for Priya, 20m'")).firstMatch
        XCTAssertTrue(block.exists)
        block.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 1.2, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.95)),
                   withVelocity: .slow, thenHoldForDuration: 1.0)
        XCTAssertTrue(app.screen("tray").staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'Planned “Write interview feedback for Priya” · Today'"))
            .firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: Working

    /// Pause shows its glyph alone; Paused and Resume follow.
    @MainActor
    func testWorkingPauseAndResume() {
        let app = launch()
        app.buttons["Open Working"].tap()
        app.waitForScreen("screen.working")
        let pause = app.buttons["working.pause"]
        XCTAssertEqual(pause.label, "Pause")
        pause.tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["working.pause"].label, "Resume")
        snap(app, "working-paused")
        app.buttons["working.pause"].tap()
        XCTAssertTrue(app.staticTexts["Working"].waitForExistence(timeout: 5))
        app.buttons["working.close"].tap()
        app.waitForScreenToClose("screen.working")
    }

    // MARK: Capture and Inbox

    @MainActor
    func testCaptureTypesTokensAndAdds() throws {
        let app = launch()
        app.dock("capture").tap()
        app.waitForScreen("screen.capture")
        let field = app.textFields["capture.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Buy yen for the trip fri 6pm ~15m #travel")
        XCTAssertTrue(app.element(beginningWith: "Saves as Fri 25, 18:00, 15 min, #travel").waitForExistence(timeout: 5))
        snap(app, "capture")
        app.buttons["Add"].tap()
        app.waitForScreenToClose("screen.capture")
        XCTAssertTrue(app.screen("tray").staticTexts["Added to Inbox"].waitForExistence(timeout: 5))
        app.dock("inbox").tap()
        app.waitForScreen("screen.inbox")
        XCTAssertTrue(app.staticTexts["7 to triage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Buy yen for the trip"].exists)
    }

    /// Triage deals the Inbox oldest first; each choice moves on.
    @MainActor
    func testTriageOneByOne() {
        let app = launch()
        app.dock("inbox").tap()
        app.waitForScreen("screen.inbox")
        snap(app, "inbox")
        app.buttons["inbox.triage"].tap()
        app.waitForScreen("screen.triage")
        XCTAssertEqual(app.staticTexts["triage.position"].label, "1 of 6")
        XCTAssertTrue(app.staticTexts["Gift ideas for Mika’s birthday"].exists)
        snap(app, "triage")
        app.buttons["triage.later"].tap()
        XCTAssertTrue(app.staticTexts["Return the library books"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["triage.position"].label, "2 of 6")
        // A day alone: picked, then Next; it waits in the Inbox.
        app.buttons["Tomorrow"].tap()
        XCTAssertFalse(app.buttons["triage.later"].exists, "Next takes Later's place once something is picked")
        app.buttons["triage.next"].tap()
        XCTAssertTrue(app.screen("tray").staticTexts["“Return the library books” due tomorrow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Look into a standing desk for the study"].waitForExistence(timeout: 5))
        // A list and a day, both picked, filed as one step.
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Home'")).firstMatch.tap()
        app.buttons["Tomorrow"].tap()
        XCTAssertTrue(app.staticTexts["Look into a standing desk for the study"].exists, "Picking doesn't deal the next card")
        snap(app, "triage-picked")
        app.buttons["triage.next"].tap()
        XCTAssertTrue(app.screen("tray").staticTexts["Moved “Look into a standing desk for the study” to Home, due tomorrow"]
            .waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Call the dentist back about the crown"].waitForExistence(timeout: 5))
        app.buttons["triage.done"].tap()
        XCTAssertTrue(app.staticTexts["Cancel the gym trial before it renews"].waitForExistence(timeout: 5))
        app.buttons["triage.delete"].tap()
        XCTAssertTrue(app.staticTexts["Send Jun the photos from Nara"].waitForExistence(timeout: 5))
        app.buttons["triage.later"].tap()
        XCTAssertTrue(app.staticTexts["Inbox triaged"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["6 reviewed this session."].exists)
        snap(app, "triage-done")
        app.buttons["Back to Inbox"].tap()
        app.waitForScreen("screen.inbox")
    }

    // MARK: Lists

    @MainActor
    func testListPageFoldAndSelect() {
        let app = launch(environment: ["OpenlistOpenRoute": "list:Weekend in Kyoto"])
        app.waitForScreen("screen.list", timeout: 20)
        XCTAssertTrue(app.staticTexts["7 open"].exists)
        app.buttons["1 done"].tap()
        XCTAssertTrue(app.buttons["Reply to Kasuga about the tatami room"].waitForExistence(timeout: 5))
        snap(app, "list-done-open")
        app.buttons["list.select"].tap()
        app.waitForScreen("screen.select")
        XCTAssertFalse(app.dock("capture").exists, "The bulk bar takes the dock's place")
        for title in ["Renew passports", "Reserve the Nishiki market tour", "Pick up JR passes at Kyoto Station"] {
            app.descendants(matching: .any).matching(identifier: "select.row")
                .matching(NSPredicate(format: "label == %@", title)).firstMatch.tap()
        }
        XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 5))
        snap(app, "select")
        app.buttons["Move to tomorrow"].tap()
        app.waitForScreenToClose("screen.select")
        XCTAssertTrue(app.screen("tray").staticTexts["3 tasks due tomorrow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.dock("capture").waitForExistence(timeout: 5))
    }

    @MainActor
    func testNewList() {
        let app = launch(environment: ["OpenlistOpenRoute": "lists"])
        app.waitForScreen("screen.lists", timeout: 20)
        snap(app, "lists")
        app.buttons["lists.new"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Garden")
        app.alerts.buttons["Create"].tap()
        app.waitForScreen("screen.list")
        XCTAssertTrue(app.staticTexts["Nothing here yet"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.dock("capture").label, "New task in Garden")
    }

    // MARK: Task detail

    @MainActor
    func testTaskDetailEdits() {
        let app = launch()
        app.buttons["Write interview feedback for Priya"].tap()
        app.waitForScreen("screen.taskDetail")
        app.buttons["detail.star"].tap()
        XCTAssertTrue(app.screen("tray").staticTexts["Starred “Write interview feedback for Priya”"].waitForExistence(timeout: 5))
        let plan = app.switches["detail.plan"]
        plan.tap()
        XCTAssertTrue(app.screen("tray").staticTexts["Planned for today: “Write interview feedback for Priya”"]
            .waitForExistence(timeout: 5))
        snap(app, "detail")
        app.buttons["detail.labels"].tap()
        XCTAssertTrue(app.buttons["#travel"].waitForExistence(timeout: 5))
        app.buttons["#travel"].tap()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.labels"].waitForExistence(timeout: 5))
        app.buttons["detail.start"].tap()
        app.waitForScreen("screen.working")
        XCTAssertTrue(app.staticTexts["Write interview feedback for Priya"].exists)
    }

    /// Subtasks go in one after another from the row under them, and the
    /// estimate slides.
    @MainActor
    func testSubtasksAndEstimate() {
        let app = launch()
        app.buttons["Write interview feedback for Priya"].tap()
        app.waitForScreen("screen.taskDetail")
        app.buttons["detail.addSubtaskStart"].tap()
        let field = app.textFields["detail.addSubtask"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Collect interview notes\n")
        XCTAssertTrue(app.buttons["Collect interview notes"].waitForExistence(timeout: 5))
        field.typeText("Send to the hiring panel\n")
        XCTAssertTrue(app.buttons["Send to the hiring panel"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.subtaskCount"].label, "0 of 2")
        snap(app, "detail-subtasks")
        let estimate = app.sliders["detail.estimate"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 5))
        XCTAssertEqual(estimate.value as? String, "20 minutes")
        estimate.adjust(toNormalizedSliderPosition: 0.5)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != '20 minutes'"), object: estimate)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 5), .completed)
        snap(app, "detail-estimate")
    }

    /// History goes to Activity, as the design links it.
    @MainActor
    func testTaskDetailHistoryOpensActivity() {
        let app = launch()
        app.buttons["Write interview feedback for Priya"].tap()
        app.waitForScreen("screen.taskDetail")
        app.buttons["detail.history"].tap()
        app.waitForScreen("screen.activity")
        app.buttons["Back to Task"].tap()
        app.waitForScreen("screen.taskDetail")
    }

    // MARK: Find

    @MainActor
    func testFindLabelAndDone() {
        let app = launch(environment: ["OpenlistOpenRoute": "lists"])
        app.waitForScreen("screen.lists", timeout: 20)
        app.buttons["#travel"].tap()
        app.waitForScreen("screen.find")
        XCTAssertTrue(app.staticTexts["4 tasks"].waitForExistence(timeout: 5))
        snap(app, "find")
        app.buttons["find.filter.done"].tap()
        XCTAssertTrue(app.staticTexts["5 tasks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Reply to Kasuga about the tatami room"].exists)
        app.buttons["find.filter.done"].tap()
        XCTAssertTrue(app.staticTexts["4 tasks"].waitForExistence(timeout: 5))
        app.buttons["find.filter.starred"].tap()
        XCTAssertTrue(app.staticTexts["1 task"].waitForExistence(timeout: 5))
    }

    // MARK: Activity, Settings and Trash

    @MainActor
    func testActivityDays() {
        let app = launch()
        app.buttons["today.done"].tap()
        app.waitForScreen("screen.activity")
        XCTAssertTrue(app.staticTexts["6-day streak · 81 done in 12 weeks"].exists)
        XCTAssertTrue(app.element(beginningWith: "Started Draft Q3 OKRs").exists)
        // The work running at launch is this session's latest step, with Undo.
        XCTAssertTrue(app.buttons["activity.undo"].exists)
        snap(app, "activity")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tuesday 22 September'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Tuesday 22 September"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(beginningWith: "Compare Gion vs Arashiyama").exists)
    }

    /// Undo on Activity's newest change takes back this session's latest step.
    @MainActor
    func testActivityUndo() {
        let app = launch()
        let tick = app.buttons["Complete Close out Q2 retro actions"]
        XCTAssertTrue(tick.waitForExistence(timeout: 10))
        tick.tap()
        // After the dwell, the completion is saved and listed.
        sleep(7)
        app.buttons["today.done"].tap()
        app.waitForScreen("screen.activity")
        XCTAssertTrue(app.element(beginningWith: "Completed Close out Q2 retro actions").waitForExistence(timeout: 5))
        snap(app, "activity-undo")
        app.buttons["activity.undo"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["activity.undo"])
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
        app.buttons["Back to Today"].tap()
        XCTAssertTrue(app.buttons["Complete Close out Q2 retro actions"].waitForExistence(timeout: 5))
    }

    /// Starting work is a step too: Activity lists it with Undo, which stops
    /// it and takes it back out.
    @MainActor
    func testStartingWorkCanBeUndoneFromActivity() {
        let app = launch()
        app.buttons["Write interview feedback for Priya"].tap()
        app.waitForScreen("screen.taskDetail")
        app.buttons["detail.start"].tap()
        app.waitForScreen("screen.working")
        app.buttons["working.close"].tap()
        app.waitForScreenToClose("screen.working")
        app.buttons["Back to Today"].tap()
        app.waitForScreen("screen.today")
        app.buttons["today.done"].tap()
        app.waitForScreen("screen.activity")
        XCTAssertTrue(app.element(beginningWith: "Started Write interview feedback for Priya").waitForExistence(timeout: 5))
        snap(app, "activity-started-undo")
        app.buttons["activity.undo"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.element(beginningWith: "Started Write interview feedback for Priya"))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
    }

    @MainActor
    func testSettingsAndTrash() {
        let app = launch(environment: ["OpenlistOpenRoute": "settings"])
        app.waitForScreen("screen.settings", timeout: 20)
        XCTAssertTrue(app.buttons["settings.planHours"].label.contains("09–17 · 18–21"))
        snap(app, "settings")
        let haptics = app.switches["settings.haptics"]
        XCTAssertEqual(haptics.value as? String, "1")
        haptics.tap()
        XCTAssertEqual(app.switches["settings.haptics"].value as? String, "0")
        app.buttons["Trash"].tap()
        app.waitForScreen("screen.trash")
        XCTAssertTrue(app.staticTexts["3 items · hold × to erase one for good"].exists)
        app.buttons["trash.restore"].firstMatch.tap()
        XCTAssertTrue(app.screen("tray").staticTexts["Restored to Q3 planning"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 items · hold × to erase one for good"].waitForExistence(timeout: 5))
        snap(app, "trash")
        app.buttons["Hold to erase Old packing list draft"].press(forDuration: 1.4)
        XCTAssertTrue(app.staticTexts["1 item · hold × to erase one for good"].waitForExistence(timeout: 5))
        app.buttons["Back to Settings"].tap()
        app.waitForScreen("screen.settings")
    }

    // MARK: Layout

    /// Scrolled to its end, a tab's page leaves its last row clear of the
    /// dock, 40 pt above it as the design's `.scroll` pads it, never under it
    /// and never twice that.
    @MainActor
    func testLongPagesScrollClearOfTheDock() {
        let app = launch()
        let done = app.buttons["today.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        for _ in 0..<3 { app.swipeUp() }
        sleep(1)
        snap(app, "today-scrolled")
        let dock = app.otherElements["Tabs"]
        XCTAssertTrue(dock.exists)
        // The tab bar's 6 pt padding sits between its buttons and the capsule's edge.
        let gap = dock.frame.minY - done.frame.maxY
        XCTAssertGreaterThanOrEqual(gap, 20, "The page's end scrolls under the dock")
        XCTAssertLessThanOrEqual(gap, 70, "The page leaves the dock's room twice")
    }

    // MARK: Helpers

    @MainActor
    private func launch(environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication.reviewSession(environment: environment)
        app.launch()
        // The first launch after the simulator boots can be slow.
        if environment["OpenlistOpenRoute"] == nil { app.waitForScreen("screen.today", timeout: 45) }
        return app
    }

    /// The screen now, attached to the test and, with a folder given, saved.
    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        // Let springs and the tray settle.
        usleep(600_000)
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

extension XCUIApplication {
    /// Any element whose label starts with `prefix`: a row read as one, with
    /// its time or detail after the title.
    func element(beginningWith prefix: String) -> XCUIElement {
        descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }
}
