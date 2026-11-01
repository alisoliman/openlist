import XCTest

/// A list's Icon & colour, from its page: the tile and the menu open it, any
/// emoji from the field, a colour and a suggestion show at once, and the
/// list keeps them.
final class ListAppearanceUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    @MainActor
    func testTheTileChangesTheListsIconAndColour() {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": "list:Weekend in Kyoto"])
        app.launch()
        app.waitForScreen("screen.list", timeout: 30)
        let tile = app.buttons["list.icon"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertEqual(tile.value as? String, "🗻")
        tile.tap()

        let field = app.textFields["appearance.emoji"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["appearance.icon.🗻"].isSelected)
        snapshot(app, "list-appearance-sheet")
        let keyboard = app.keyboards.firstMatch
        focus(field, keyboard: keyboard)
        field.typeText("🦊")
        let fox = app.staticTexts["🦊"]
        XCTAssertTrue(fox.waitForExistence(timeout: 5), "An emoji of the list's own shows beside the field")
        XCTAssertFalse(app.buttons["appearance.icon.🗻"].isSelected)
        XCTAssertEqual(field.value as? String, "Any emoji", "The field empties for the next")
        XCTAssertTrue(waitForAbsence(of: keyboard), "The pick puts the keyboard away")
        snapshot(app, "list-appearance-own-emoji")
        focus(field, keyboard: keyboard)
        field.typeText("abc")
        XCTAssertEqual(field.value as? String, "Any emoji", "Letters are no icon")
        XCTAssertTrue(fox.exists)

        let teal = app.buttons["appearance.colour.teal"]
        reveal(teal, in: app)
        teal.tap()
        XCTAssertTrue(teal.isSelected)
        XCTAssertFalse(app.buttons["appearance.colour.violet"].isSelected)
        app.buttons["Done"].tap()
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertEqual(tile.value as? String, "🦊")

        app.terminate()
        app.launch()
        app.waitForScreen("screen.list", timeout: 30)
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertEqual(tile.value as? String, "🦊", "The list keeps its icon")
        app.buttons["list.options"].tap()
        // The menu's item, which shares its name with the tile.
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Icon & colour", "list.icon")).firstMatch.tap()
        XCTAssertTrue(fox.waitForExistence(timeout: 5))
        let seedling = app.buttons["appearance.icon.🌱"]
        seedling.tap()
        XCTAssertTrue(seedling.isSelected)
        XCTAssertTrue(waitForAbsence(of: fox), "A suggestion takes the place of the list's own")
        reveal(teal, in: app)
        XCTAssertTrue(teal.isSelected, "The list keeps its colour")
    }

    /// Taps `field` until the keyboard is up: a loaded simulator can drop the
    /// first tap while it brings up its first keyboard.
    @MainActor
    private func focus(_ field: XCUIElement, keyboard: XCUIElement) {
        for _ in 0..<2 where !keyboard.exists {
            field.tap()
            _ = keyboard.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(keyboard.exists)
    }

    /// Scrolls the sheet, which puts any keyboard away, until `element` is
    /// on screen. The drag starts high in the sheet, clear of the keyboard,
    /// whose keys a swipe would type.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["appearance.scroll"]
        for _ in 0..<4 where !(element.exists && element.isHittable && !app.keyboards.firstMatch.exists) {
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -160)))
        }
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(element.isHittable)
    }

    @MainActor
    private func waitForAbsence(of element: XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: 5) == .completed
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
