//
//  LaunchTests.swift
//  OpenlistiOSUITests
//

import XCTest

final class LaunchTests: XCTestCase {
    /// A review session launches straight into Today, with its dock.
    @MainActor
    func testLaunchesIntoToday() {
        let app = XCUIApplication.reviewSession()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        app.waitForScreen("screen.today", timeout: 20)
        XCTAssertTrue(app.dock("today").isSelected)
        XCTAssertTrue(app.dock("inbox").exists)
        XCTAssertEqual(app.dock("inbox").label, "Inbox, 6 to triage")
    }
}
