//
//  KeyboardTyping.swift
//  OpenlistiOSUITests
//

import XCTest

extension XCUIApplication {
    /// Types `text` into `field`, then waits for the on-screen keyboard to be
    /// back if the typing put it away. `typeText` types on a virtual hardware
    /// keyboard, and while one is attached iOS can minimize the on-screen
    /// keyboard, bringing it back about a second after the last key. What
    /// rides on the keyboard, such as Capture's sheet, slides back up with it,
    /// and a tap during the slide misses: Capture's Add didn't close the sheet.
    /// Whether the keyboard goes away varies by machine and run, so tap
    /// nothing that rides on it straight after `typeText`; type with this.
    func type(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = keyboards.firstMatch
        let wasUp = keyboard.exists && keyboard.isHittable
        field.typeText(text)
        // Up before, so it comes back, unless the field has let it go.
        guard wasUp else { return }
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR hittable == true"),
                                                object: keyboard)
        XCTAssertEqual(XCTWaiter().wait(for: [settled], timeout: 10), .completed,
                       "The keyboard didn't come back after typing", file: file, line: line)
    }
}
