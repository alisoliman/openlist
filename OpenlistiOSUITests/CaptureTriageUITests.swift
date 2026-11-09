//
//  CaptureTriageUITests.swift
//  OpenlistiOSUITests
//

import UIKit
import XCTest

/// Adding and triaging, as the quality-of-life pass changed them: lines pasted
/// into Capture as rows, `@list` and `#label` suggestions, a token kept as
/// text, a note, Return adding and staying for the next; triage's Snooze and
/// the Snoozed group, its edit line, Details and More; Select on the Inbox;
/// and the searchable list picker behind a row's Move to list.
final class CaptureTriageUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: Capture

    /// Lines pasted at once wait as rows, each read for its own tokens, and
    /// Add saves them all; the typed text stays.
    @MainActor
    func testPastedLinesBecomeRows() {
        let app = launch(route: "inbox")
        app.dock("capture").tap()
        app.waitForScreen("screen.capture")
        let field = app.textFields["capture.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        UIPasteboard.general.string = "- [ ] Pack the adapter\n- [x] Print the tickets\n- Buy yen tomorrow @Weekend in Kyoto"
        field.press(forDuration: 1.2)
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "The field offers Paste")
        paste.tap()
        // A system prompt can ask once before an app reads what another copied.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        else if app.alerts.buttons["Allow Paste"].exists { app.alerts.buttons["Allow Paste"].tap() }
        let heard = app.screen("capture.heard")
        XCTAssertTrue(heard.waitForExistence(timeout: 5), "Pasted lines wait as rows")
        XCTAssertTrue(app.staticTexts["Pack the adapter"].exists)
        XCTAssertTrue(app.staticTexts["Buy yen"].exists)
        XCTAssertFalse(app.staticTexts["Print the tickets"].exists, "A done item is left out")
        snap(app, "capture-pasted-rows")
        app.screen("screen.capture").buttons["Add 2"].tap()
        app.waitForScreenToClose("screen.capture")
        XCTAssertTrue(app.buttons["Pack the adapter"].waitForExistence(timeout: 5), "A row naming no list goes to the Inbox")
        XCTAssertFalse(app.buttons["Buy yen"].exists, "A row naming a list goes there")
    }

    /// `@` suggests lists and fills one in; Return adds and keeps Capture,
    /// aimed at the same list, for the next; Done closes it.
    @MainActor
    func testListSuggestionAndAddAnother() {
        let app = launch(route: "inbox")
        app.dock("capture").tap()
        app.waitForScreen("screen.capture")
        let field = app.textFields["capture.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.type("Order a doormat @Ho", into: field)
        let home = app.buttons["List Home"]
        XCTAssertTrue(home.waitForExistence(timeout: 5), "@ suggests the lists whose names start so")
        snap(app, "capture-list-suggestion")
        home.tap()
        XCTAssertEqual(field.value as? String, "Order a doormat @Home ")
        app.type("\n", into: field)
        let added = app.screen("capture.added")
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        XCTAssertEqual(added.label, "Added “Order a doormat” to Home")
        // An empty field reads its placeholder.
        XCTAssertEqual(field.value as? String, "New task", "Return clears the field for the next task")
        app.type("Fix the gate latch\n", into: field)
        let second = NSPredicate(format: "label == %@", "Added “Fix the gate latch” to Home")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: second, object: added)], timeout: 5), .completed,
                       "The next task goes to the same list")
        snap(app, "capture-added-another")
        app.screen("screen.capture").buttons["Done"].tap()
        app.waitForScreenToClose("screen.capture")
        XCTAssertTrue(app.staticTexts["6 to triage"].waitForExistence(timeout: 5), "Both went to Home, not the Inbox")
        XCTAssertFalse(app.buttons["Order a doormat"].exists)
    }

    /// A weekday's short name read as a date goes back to being words from
    /// the date chip's menu; a note saves with the task.
    @MainActor
    func testKeepAsTextAndNote() {
        let app = launch(route: "inbox")
        app.dock("capture").tap()
        app.waitForScreen("screen.capture")
        let field = app.textFields["capture.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        app.type("Buy sun cream", into: field)
        let due = app.buttons["capture.dueDate"]
        XCTAssertEqual(due.value as? String, "Sun 27", "Sun reads as Sunday")
        due.tap()
        let keep = app.buttons["Keep “sun” as text"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        keep.tap()
        XCTAssertEqual(due.value as? String, "None")
        app.buttons["capture.addNote"].tap()
        let note = app.textFields["capture.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        app.type("SPF 50, the blue tube", into: note)
        snap(app, "capture-kept-and-note")
        app.screen("screen.capture").buttons["Add"].tap()
        app.waitForScreenToClose("screen.capture")
        let task = app.buttons["Buy sun cream"]
        XCTAssertTrue(task.waitForExistence(timeout: 5), "The words stay in the title")
        task.tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertEqual(app.textFields["detail.note"].value as? String, "SPF 50, the blue tube")
        XCTAssertTrue(app.buttons["detail.when"].label.contains("None"))
    }

    // MARK: Triage

    /// Snooze takes the card off the pass until its day; the Inbox keeps it
    /// at the end, with the day it's back.
    @MainActor
    func testSnoozeFromTriage() {
        let app = launch(route: "triage")
        app.waitForScreen("screen.triage", timeout: 20)
        XCTAssertTrue(app.staticTexts["Gift ideas for Mika’s birthday"].waitForExistence(timeout: 5))
        app.buttons["triage.snooze"].tap()
        let tomorrow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tomorrow'")).firstMatch
        XCTAssertTrue(tomorrow.waitForExistence(timeout: 5))
        snap(app, "triage-snooze-menu")
        tomorrow.tap()
        XCTAssertTrue(app.staticTexts["Return the library books"].waitForExistence(timeout: 5), "The next card comes")
        XCTAssertEqual(app.staticTexts["triage.position"].label, "2 of 6")
        app.buttons["triage.close"].tap()
        app.waitForScreen("screen.inbox")
        XCTAssertTrue(app.staticTexts["5 to triage"].waitForExistence(timeout: 5), "A snoozed task isn't one to triage")
        app.screen("screen.inbox").swipeUp()
        let snoozed = app.screen("inbox.snoozed")
        XCTAssertTrue(snoozed.waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(beginningWith: "Gift ideas for Mika’s birthday").exists)
        snap(app, "inbox-snoozed")
    }

    /// A tap on the title edits it: a new title and tokens; the day and the
    /// list it names are picked for Next, which files it in one step.
    @MainActor
    func testEditLineThenNext() {
        let app = launch(route: "triage")
        app.waitForScreen("screen.triage", timeout: 20)
        let title = app.buttons["triage.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        let edit = app.textFields["triage.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        app.type(" #travel @Home fri", into: edit)
        snap(app, "triage-edit-line")
        app.buttons["triage.editDone"].tap()
        XCTAssertTrue(app.staticTexts["Gift ideas for Mika’s birthday"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Date, Fri 25"].waitForExistence(timeout: 5), "The day it named is picked")
        XCTAssertTrue(app.buttons["triage.next"].exists, "Next files what's picked")
        app.buttons["triage.next"].tap()
        let moved = app.staticTexts.matching(NSPredicate(format: "label == %@",
                                                         "Moved “Gift ideas for Mika’s birthday” to Home, due Fri")).firstMatch
        XCTAssertTrue(moved.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Return the library books"].waitForExistence(timeout: 5))
    }

    /// Details opens the card's task over triage; Back returns to the card.
    @MainActor
    func testDetailsFromTheCard() {
        let app = launch(route: "triage")
        app.waitForScreen("screen.triage", timeout: 20)
        let details = app.buttons["triage.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        details.tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertEqual(app.textFields["detail.title"].value as? String, "Gift ideas for Mika’s birthday")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Back'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Gift ideas for Mika’s birthday"].waitForExistence(timeout: 5))
    }

    // MARK: Inbox

    /// Select on the Inbox files several captures at once through the list
    /// picker, which finds a list by name.
    @MainActor
    func testSelectOnTheInboxFilesSeveral() {
        let app = launch(route: "inbox")
        app.waitForScreen("screen.inbox", timeout: 20)
        app.buttons["inbox.select"].tap()
        app.waitForScreen("screen.select")
        let rows = app.buttons.matching(identifier: "select.row")
        rows.element(boundBy: 0).tap()
        rows.element(boundBy: 1).tap()
        app.buttons["Move to another list"].tap()
        let picker = app.waitForScreen("screen.listPicker")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        app.type("read", into: search)
        snap(app, "list-picker-search")
        let reading = picker.buttons["Reading"]
        XCTAssertTrue(reading.waitForExistence(timeout: 5))
        XCTAssertFalse(picker.buttons["Home"].exists, "Typing narrows the lists")
        reading.tap()
        XCTAssertTrue(app.screen("tray").staticTexts["Moved 2 tasks to Reading"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["4 to triage"].waitForExistence(timeout: 5))
    }

    // MARK: Helpers

    @MainActor
    private func launch(route: String) -> XCUIApplication {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": route])
        app.launch()
        return app
    }

    /// The screen now, attached to the test and, with a folder given, saved.
    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
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
