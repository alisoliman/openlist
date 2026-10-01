//
//  ListsTasksUITests.swift
//  OpenlistiOSUITests
//

import XCTest

/// The Lists task view is useful only if it really combines sources and
/// retains their context while using the usual task detail and actions.
final class ListsTasksUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCombinedTasksShowTheirSourcesAndOpenTheCorrectDetail() {
        let app = launch()
        app.buttons["lists.view.tasks"].tap()
        XCTAssertTrue(app.buttons["lists.view.tasks"].isSelected)
        let home = app.buttons["Fix the dripping bathroom tap"]
        let work = app.buttons["Close out Q2 retro actions"]
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertTrue(work.exists, "Tasks from distinct lists appear in the same overview")
        XCTAssertTrue((home.value as? String)?.contains("Home") == true)
        XCTAssertTrue((work.value as? String)?.contains("Q3 planning") == true)
        XCTAssertFalse(app.buttons["Try the new ramen place"].exists, "Trashed tasks stay out of the overview")
        XCTAssertFalse(app.buttons["Standup notes"].exists, "Completed tasks stay out of the open overview")
        snapshot(app, "lists-tasks-all")
        home.tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertEqual(app.textFields["detail.title"].value as? String, "Fix the dripping bathroom tap")
        XCTAssertTrue(app.buttons["detail.list"].label.contains("Home"))
        app.buttons["Back to Lists"].tap()
        app.waitForScreen("screen.lists")
        XCTAssertTrue(app.buttons["lists.view.tasks"].isSelected)
    }

    @MainActor
    func testChooseMultipleListsThenShowAllAgain() {
        let app = launch()
        app.buttons["lists.view.tasks"].tap()
        choose("Reading", in: app)
        XCTAssertEqual(app.buttons["lists.filter"].value as? String, "Reading")
        XCTAssertTrue(app.buttons["Start Piranesi"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Close out Q2 retro actions"].exists)
        choose("Home", in: app)
        XCTAssertEqual(app.buttons["lists.filter"].value as? String, "2 lists")
        XCTAssertTrue(app.buttons["Fix the dripping bathroom tap"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start Piranesi"].exists)
        XCTAssertFalse(app.buttons["Close out Q2 retro actions"].exists)
        snapshot(app, "lists-tasks-two-sources")
        app.buttons["lists.filter"].tap()
        app.buttons["lists.filter.all"].tap()
        XCTAssertEqual(app.buttons["lists.filter"].value as? String, "All lists")
        XCTAssertTrue(app.buttons["Close out Q2 retro actions"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTaskViewChoicePersistsAndCardsStillOpenLists() {
        let app = launch()
        app.buttons["lists.view.tasks"].tap()
        app.terminate()
        app.launch()
        app.waitForScreen("screen.lists", timeout: 30)
        XCTAssertTrue(app.buttons["lists.view.tasks"].isSelected)
        XCTAssertTrue(app.buttons["Fix the dripping bathroom tap"].exists)
        app.buttons["lists.view.cards"].tap()
        XCTAssertTrue(app.buttons["lists.view.cards"].isSelected)
        XCTAssertTrue(app.buttons["Weekend in Kyoto"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Weekend in Kyoto"].firstMatch.tap()
        app.waitForScreen("screen.list")
        XCTAssertTrue(app.buttons["Renew passports"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testArchivingASelectedListClearsItsStaleFilter() {
        let app = launch()
        app.buttons["lists.view.tasks"].tap()
        choose("Reading", in: app)
        XCTAssertEqual(app.buttons["lists.filter"].value as? String, "Reading")
        app.buttons["lists.view.cards"].tap()
        let reading = app.buttons["Reading"].firstMatch
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        reading.press(forDuration: 1)
        app.buttons["Archive"].tap()
        app.buttons["lists.view.tasks"].tap()
        XCTAssertEqual(app.buttons["lists.filter"].value as? String, "All lists")
        XCTAssertFalse(app.buttons["Start Piranesi"].exists)
        XCTAssertTrue(app.buttons["Close out Q2 retro actions"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testTaskOverviewScrollsWithoutRevealingSwipeActions() {
        let app = launch()
        app.buttons["lists.view.tasks"].tap()
        let row = app.buttons["Fix the dripping bathroom tap"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let y = row.frame.minY
        let initialMetadata = row.value as? String
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 12, dy: -180)))
        XCTAssertFalse(app.buttons["task.swipe.first"].exists)
        XCTAssertFalse(app.buttons["task.swipe.delete"].exists)
        snapshot(app, "lists-tasks-after-vertical-scroll")
        // "tray" is also the Inbox dock symbol's identifier. Undo uniquely
        // identifies an actual task mutation, and the row must retain its state.
        XCTAssertFalse(app.buttons["tray.action"].exists, "A vertical scroll must not create an undoable task mutation")
        XCTAssertEqual(row.value as? String, initialMetadata)
        XCTAssertTrue(app.buttons["Complete Fix the dripping bathroom tap"].exists)
        XCTAssertLessThan(row.frame.minY, y, "A vertical drag on a task keeps scrolling the page")
    }

    @MainActor
    func testLargeTypeKeepsViewChoiceFiltersAndTaskDetailReachable() {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": "lists"])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        app.waitForScreen("screen.lists", timeout: 45)
        XCTAssertTrue(app.buttons["lists.view.tasks"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["lists.view.tasks"].frame.height, 44)
        app.buttons["lists.view.tasks"].tap()
        choose("Home", in: app)
        let task = app.buttons["Fix the dripping bathroom tap"]
        for _ in 0..<5 where !task.isHittable { app.swipeUp() }
        XCTAssertTrue(task.isHittable)
        snapshot(app, "lists-tasks-large-type")
        task.tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertEqual(app.textFields["detail.title"].value as? String, "Fix the dripping bathroom tap")
    }

    @MainActor
    func testWorkTabOpensAndReturnsToOtherTabs() {
        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 45)
        XCTAssertTrue(app.dock("work").isHittable)
        app.dock("work").tap()
        app.waitForScreen("screen.work")
        XCTAssertTrue(app.dock("work").isSelected)
        XCTAssertFalse(app.dock("today").isSelected)
        snapshot(app, "work-tab")
        app.dock("lists").tap()
        app.waitForScreen("screen.lists")
        app.dock("today").tap()
        app.waitForScreen("screen.today")
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": "lists"])
        app.launch()
        let appeared = app.screen("screen.lists").waitForExistence(timeout: 45)
        if !appeared { snapshot(app, "lists-launch-failure") }
        XCTAssertTrue(appeared, "Lists did not appear at launch. \(app.debugDescription)")
        return app
    }

    @MainActor
    private func choose(_ name: String, in app: XCUIApplication) {
        let filter = app.buttons["lists.filter"]
        for _ in 0..<5 where !filter.isHittable { app.swipeUp() }
        filter.tap()
        let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'lists.filter.' AND label == %@", name)).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
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
