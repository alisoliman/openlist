//
//  InteractionUITests.swift
//  OpenlistiOSUITests
//

import XCTest

/// What the screens say and offer at their edges: a name before Create, an
/// empty list that says so, Find's way out of no results, Trash's × asking
/// on a tap, the timeline's block menu, and a swipe that can't apply saying
/// why.
final class InteractionUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Create waits for a name. The new list's dimmed Select says why on a
    /// tap, and its card says it's empty rather than all done.
    @MainActor
    func testNewListNeedsANameAndSaysItIsEmpty() {
        let app = launch("lists")
        app.buttons["lists.new"].tap()
        let create = app.alerts.buttons["Create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertFalse(create.isEnabled, "Create waits for a name")
        let name = app.alerts.textFields.firstMatch
        name.tap()
        name.typeText("   ")
        XCTAssertFalse(create.isEnabled, "Spaces aren't a name")
        name.typeText("Garden")
        XCTAssertTrue(create.isEnabled)
        create.tap()
        app.waitForScreen("screen.list")
        XCTAssertTrue(app.staticTexts["Empty"].waitForExistence(timeout: 5), "Not all done: there's nothing yet")
        let select = app.buttons["list.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        XCTAssertFalse(select.isEnabled, "Nothing open to select")
        select.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.screen("tray").staticTexts["No open tasks to select"].waitForExistence(timeout: 5))
        snapshot(app, "list-new-select-hint")
        app.buttons["Back to Lists"].tap()
        app.waitForScreen("screen.lists")
        let card = app.buttons["Garden"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "Empty")
        XCTAssertEqual(app.buttons["Reading"].firstMatch.value as? String, "2 open")
    }

    /// No results offers the done tasks that would match, and a way back to
    /// an empty search.
    @MainActor
    func testFindWithNoResultsOffersDoneTasksAndClearing() {
        let app = launch("find:#travel kasuga", screen: "find")
        let include = app.buttons["Include done tasks"]
        XCTAssertTrue(include.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Clear search"].exists)
        snapshot(app, "find-no-results-done")
        include.tap()
        XCTAssertTrue(app.buttons["Reply to Kasuga about the tatami room"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 task"].exists)

        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("zebra")
        let clear = app.buttons["Clear search"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        // The search runs off the main thread: wait for its answer.
        XCTAssertTrue(include.waitForNonExistence(timeout: 5), "No done task matches either")
        snapshot(app, "find-no-results")
        clear.tap()
        XCTAssertTrue(app.staticTexts["Type words, or add a #label, a list’s name, today, overdue, starred or done."]
            .waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["#travel, filter"].exists, "Clearing takes the chips out")
    }

    /// The field's clear button empties its chips and words.
    @MainActor
    func testSearchFieldClearButton() {
        let app = launch("find:#travel", screen: "find")
        XCTAssertTrue(app.staticTexts["4 tasks"].waitForExistence(timeout: 5))
        app.buttons["Clear"].tap()
        XCTAssertTrue(app.staticTexts["Type words, or add a #label, a list’s name, today, overdue, starred or done."]
            .waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Clear"].exists)
    }

    /// A plain tap on × asks before erasing for good; holding still erases.
    @MainActor
    func testTrashCrossAsksOnATap() {
        let app = launch("trash")
        XCTAssertTrue(app.staticTexts["3 items · hold × to erase one for good"].exists)
        app.buttons["Hold to erase Old packing list draft"].tap()
        let erase = app.buttons["Erase"]
        XCTAssertTrue(erase.waitForExistence(timeout: 5), "A tap asks")
        XCTAssertTrue(app.staticTexts["3 items · hold × to erase one for good"].exists, "Nothing is erased yet")
        snapshot(app, "trash-tap-asks")
        erase.tap()
        XCTAssertTrue(app.staticTexts["2 items · hold × to erase one for good"].waitForExistence(timeout: 5))
        app.buttons["Hold to erase Try the new ramen place"].press(forDuration: 1.4)
        XCTAssertTrue(app.staticTexts["1 item · hold × to erase one for good"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Erase"].exists, "A hold doesn't ask")
    }

    /// A planned block's menu moves it by a quarter hour or takes it off the
    /// calendar, as VoiceOver's actions do.
    @MainActor
    func testTimelineBlockMenu() {
        let app = launch("timeline")
        let block = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Update the design role scorecard, 13:00 to 13:30'")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        block.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Move 15 minutes earlier"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Move 15 minutes later"].exists)
        snapshot(app, "timeline-block-menu")
        app.buttons["Take off the calendar"].tap()
        XCTAssertTrue(app.screen("tray").staticTexts["Took “Update the design role scorecard” off the calendar"]
            .waitForExistence(timeout: 5))
    }

    /// A full swipe on an archived list's task says why it can't go on Today.
    @MainActor
    func testFullSwipeThatCannotPlanSaysWhy() {
        let app = launch("lists")
        app.buttons["Reading"].firstMatch.press(forDuration: 1)
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.staticTexts["Archived “Reading”"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchEnvironment["OpenlistOpenRoute"] = "list:Reading"
        app.launch()
        app.waitForScreen("screen.list", timeout: 30)
        let row = app.screen("task.swipe.Start Piranesi")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)))
        XCTAssertTrue(app.screen("tray").staticTexts["“Reading” is archived"].waitForExistence(timeout: 5))
        snapshot(app, "swipe-archived-says-why")
    }

    @MainActor
    private func launch(_ route: String, screen: String? = nil) -> XCUIApplication {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": route])
        app.launch()
        app.waitForScreen("screen.\(screen ?? route)", timeout: 45)
        return app
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
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
