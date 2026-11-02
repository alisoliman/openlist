//
//  CaptureDiscard.swift
//  OpenlistiOSUITests
//

import XCTest

extension XCUIApplication {
    /// Cancels Capture holding a draft: Cancel asks first, and Discard throws
    /// the draft away and closes the sheet.
    func discardCapture(file: StaticString = #filePath, line: UInt = #line) {
        screen("screen.capture").buttons["Cancel"].tap()
        let discard = buttons["Discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5), "Cancel didn’t ask before discarding", file: file, line: line)
        discard.tap()
        waitForScreenToClose("screen.capture", file: file, line: line)
    }
}
