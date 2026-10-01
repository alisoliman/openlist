import XCTest

/// Uses the real review fixture's existing subtree. Disclosure changes are
/// saved, and the same task still supports its shared gestures and detail.
final class ListDocumentUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testSubtaskDisclosurePersistsAndSharedSwipeStillWorks() {
        let app = launch()
        let disclosure = app.buttons["Subtasks of Book the ryokan"]
        reveal(disclosure, in: app)
        XCTAssertEqual(disclosure.value as? String, "Expanded, 1 of 3 done")
        disclosure.tap()
        XCTAssertEqual(disclosure.value as? String, "Collapsed, 1 of 3 done")
        let child = app.buttons["Email Kasuga about the tatami room"]
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: child)
        XCTAssertEqual(XCTWaiter().wait(for: [hidden], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["7 open"].exists, "Folding changes visibility, not the document's open count")

        app.terminate()
        app.launch()
        app.waitForScreen("screen.list", timeout: 30)
        reveal(disclosure, in: app)
        XCTAssertEqual(disclosure.value as? String, "Collapsed, 1 of 3 done", "Stored collapse survives relaunch")
        disclosure.tap()
        XCTAssertTrue(child.waitForExistence(timeout: 5))
        XCTAssertEqual(disclosure.value as? String, "Expanded, 1 of 3 done")

        let task = app.descendants(matching: .any).matching(identifier: "task.swipe.Book the ryokan").firstMatch
        let start = task.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 112, dy: 0)))
        let star = task.buttons["task.swipe.second"]
        XCTAssertTrue(star.waitForExistence(timeout: 5))
        XCTAssertEqual(star.label, "Unstar")
        star.tap()
        XCTAssertTrue(app.staticTexts["Unstarred “Book the ryokan”"].waitForExistence(timeout: 5))
        app.buttons["tray.action"].tap()
        XCTAssertEqual(disclosure.value as? String, "Expanded, 1 of 3 done")

        app.buttons["Book the ryokan"].tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertEqual(app.textFields["detail.title"].value as? String, "Book the ryokan")
        XCTAssertEqual(app.staticTexts["detail.subtaskCount"].label, "1 of 3")
    }

    @MainActor
    func testBulkSelectionUsesVisibleOpenTasksAfterDisclosure() {
        let app = launch()
        let disclosure = app.buttons["Subtasks of Book the ryokan"]
        reveal(disclosure, in: app)
        disclosure.tap()
        reveal(app.buttons["list.select"], in: app)
        app.buttons["list.select"].tap()
        app.waitForScreen("screen.select")
        app.buttons["select.all"].tap()
        XCTAssertTrue(app.staticTexts["5 selected"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "select.row")
            .matching(NSPredicate(format: "label == %@", "Email Kasuga about the tatami room")).firstMatch.exists)
        app.buttons["select.done"].tap()
        app.waitForScreenToClose("screen.select")
        reveal(disclosure, in: app)
        disclosure.tap()
        reveal(app.buttons["list.select"], in: app)
        app.buttons["list.select"].tap()
        app.waitForScreen("screen.select")
        app.buttons["select.all"].tap()
        XCTAssertTrue(app.staticTexts["7 selected"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "select.row")
            .matching(NSPredicate(format: "label == %@", "Compare Gion vs Arashiyama")).firstMatch.exists)
    }

    @MainActor
    func testDocumentSectionsAndTaskFoldsInLightAppearance() {
        checkDocument(appearance: "light")
    }

    @MainActor
    func testDocumentSectionsAndTaskFoldsInDarkAppearanceWithReduceMotion() {
        checkDocument(appearance: "dark")
    }

    @MainActor
    func testDocumentSectionsAndTaskFoldsAtAccessibilityXXXL() {
        checkDocument(appearance: "light", largeType: true)
    }

    @MainActor
    private func checkDocument(appearance: String, largeType: Bool = false) {
        let app = XCUIApplication.reviewSession(environment: [
            "OpenlistDocumentFixture": "1",
            "OpenlistOpenRoute": "list:Document review",
        ])
        app.launchArguments += ["-settings.appearance", appearance]
        if appearance == "dark" {
            // The existing preference feeds PhoneRootView's OLStyle, whose
            // animation helper is also used by both document disclosures.
            app.launchArguments += ["-settings.reducesMotion", "YES"]
        }
        if largeType {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        app.waitForScreen("screen.list", timeout: 30)
        let prefix = "list-document-\(largeType ? "xxxl" : appearance)"
        let heading = app.buttons["Before we go"]
        let branch = app.buttons["Subtasks of Renew passports"]
        let firstNote = app.staticTexts["Bring the travel folder."]
        let nextHeading = app.buttons["In Kyoto"]
        let nextNoteText = "Ryokan check-in is at 15:00. Leave the bags at reception if we arrive early."
        let nextNote = app.staticTexts[nextNoteText]
        reveal(heading, in: app)
        XCTAssertEqual(heading.value as? String, "Expanded")
        XCTAssertEqual(branch.value as? String, "Collapsed, 1 of 2 done")
        if largeType {
            XCTAssertGreaterThan(heading.frame.height, 65, "The document must actually render at accessibility XXXL")
        }
        snapshot(app, "\(prefix)-expanded")
        reveal(firstNote, in: app)
        snapshot(app, "\(prefix)-first-note")
        reveal(heading, in: app)
        heading.tap()
        XCTAssertEqual(heading.value as? String, "Collapsed")
        XCTAssertFalse(branch.exists, "The parent task belongs to the folded heading's section")
        XCTAssertFalse(firstNote.exists, "The paragraph belongs to the folded heading's section")
        reveal(nextHeading, in: app)
        XCTAssertEqual(nextHeading.value as? String, "Expanded")
        reveal(nextNote, in: app)
        snapshot(app, "\(prefix)-section-collapsed")

        app.terminate()
        app.launch()
        app.waitForScreen("screen.list", timeout: 30)
        reveal(heading, in: app)
        XCTAssertEqual(heading.value as? String, "Collapsed", "The heading fold is stored across relaunch")
        heading.tap()
        reveal(branch, in: app)
        XCTAssertEqual(branch.value as? String, "Collapsed, 1 of 2 done", "Opening a section preserves its task's own fold")
        branch.tap()
        XCTAssertEqual(branch.value as? String, "Expanded, 1 of 2 done")
        let child = app.buttons["Submit the passport applications"]
        reveal(child, in: app)
        XCTAssertTrue(app.buttons["Get passport photos"].exists)
        snapshot(app, "\(prefix)-subtasks-expanded")

        reveal(app.buttons["list.select"], in: app)
        app.buttons["list.select"].tap()
        app.waitForScreen("screen.select")
        app.buttons["select.all"].tap()
        XCTAssertTrue(app.staticTexts["3 selected"].waitForExistence(timeout: 5))
        let selectedRows = app.descendants(matching: .any).matching(identifier: "select.row")
        for text in ["Before we go", "Bring the travel folder.", "In Kyoto", nextNoteText, "Get passport photos"] {
            XCTAssertFalse(selectedRows.matching(NSPredicate(format: "label == %@", text)).firstMatch.exists,
                           "Bulk selection must contain open tasks only")
        }
        snapshot(app, "\(prefix)-tasks-only-selection")
        app.buttons["select.done"].tap()
        app.waitForScreenToClose("screen.select")

        app.terminate()
        app.launchEnvironment["OpenlistOpenRoute"] = "list:Travel notes"
        app.launch()
        app.waitForScreen("screen.list", timeout: 30)
        let note = app.staticTexts["Keep the train confirmation here."]
        reveal(note, in: app)
        XCTAssertFalse(app.staticTexts["Nothing here yet"].exists, "Prose is document content even without tasks")
        XCTAssertFalse(app.buttons["list.select"].isEnabled)
        snapshot(app, "\(prefix)-paragraph-only")
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": "list:Weekend in Kyoto"])
        app.launch()
        app.waitForScreen("screen.list", timeout: 30)
        return app
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let top = app.statusBars.firstMatch.exists ? app.statusBars.firstMatch.frame.maxY : app.frame.minY
        let bottom = app.dock("capture").frame.minY
        for _ in 0..<12 {
            if element.exists, element.isHittable, element.frame.minY >= top, element.frame.maxY <= bottom { break }
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
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(app.frame.contains(element.frame))
        XCTAssertLessThanOrEqual(element.frame.maxY, app.dock("capture").frame.minY)
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
