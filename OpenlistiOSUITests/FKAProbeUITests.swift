import UIKit
import XCTest

/// Temporary experiment: enable Full Keyboard Access in Settings before
/// testing keyboard traversal. Runs only on an isolated CI simulator.
@MainActor
final class FKAProbeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSidebarKeyboardWithFullKeyboardAccessEnabled() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires iPad")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let accessibility = settings.buttons["com.apple.settings.accessibility"].firstMatch
        for _ in 0..<8 where !accessibility.isHittable { settings.swipeUp() }
        guard accessibility.waitForExistence(timeout: 10), accessibility.isHittable else {
            XCTFail("Settings Accessibility not found:\n\(settings.debugDescription)")
            return
        }
        accessibility.tap()
        let keyboard = settings.buttons["Keyboards & Typing"].firstMatch
        for _ in 0..<10 where !keyboard.isHittable { settings.swipeUp() }
        guard keyboard.waitForExistence(timeout: 10), keyboard.isHittable else {
            XCTFail("Keyboards & Typing not found:\n\(settings.debugDescription)")
            return
        }
        keyboard.tap()
        let fkaRow = settings.buttons["FULL_KEYBOARD_ACCESS"].firstMatch
        guard fkaRow.waitForExistence(timeout: 10) else {
            XCTFail("Full Keyboard Access row not found:\n\(settings.debugDescription)")
            return
        }
        fkaRow.tap()
        let fka = settings.switches.matching(NSPredicate(format: "identifier == %@ OR label == %@", "FULL_KEYBOARD_ACCESS", "Full Keyboard Access")).firstMatch
        guard fka.waitForExistence(timeout: 10) else {
            XCTFail("Full Keyboard Access switch not found:\n\(settings.debugDescription)")
            return
        }
        if (fka.value as? String) != "1" { fka.tap() }
        XCTAssertEqual(fka.value as? String, "1", "FKA must be enabled before the keyboard test")

        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)
        let lists = app.descendants(matching: .any).matching(identifier: "sidebar.lists").firstMatch
        let work = app.descendants(matching: .any).matching(identifier: "sidebar.work").firstMatch
        XCTAssertTrue(lists.waitForExistence(timeout: 10))
        for _ in 0..<40 where !lists.hasFocus {
            app.typeKey(XCUIKeyboardKey.tab.rawValue, modifierFlags: [])
        }
        XCTAssertTrue(lists.hasFocus, "Full Keyboard Access is on, but Tab could not reach Lists; hierarchy:\n\(app.debugDescription)")
        guard lists.hasFocus else { return }
        app.typeKey(XCUIKeyboardKey.downArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(work.hasFocus, "Down Arrow should move from Lists to Work; hierarchy:\n\(app.debugDescription)")
        guard work.hasFocus else { return }
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        app.waitForScreen("screen.work")
        XCTAssertTrue(work.isSelected)
    }
}
