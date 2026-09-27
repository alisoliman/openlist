//
//  ReviewLaunch.swift
//  OpenlistiOSUITests
//

import Foundation
import XCTest

extension XCUIApplication {
    /// The mockups' moment, which the app's fixture is written for
    /// (OpenlistiOS/Fixtures/PhoneFixture.swift).
    static let mockupNow = "2026-09-23T10:40:00"

    /// The app in a fresh review session: its own store, media and defaults,
    /// iCloud off, no system notifications, and the iPhone fixture seeded
    /// (Shared/ReviewSession.swift reads the variable in Debug builds only).
    /// `now`, an ISO 8601 date, pins the fixture's clock.
    static func reviewSession(now: String? = mockupNow, environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["OpenlistReviewSession"] = "UITest-\(UUID().uuidString)"
        if let now { app.launchEnvironment["OpenlistFixtureNow"] = now }
        for (key, value) in environment { app.launchEnvironment[key] = value }
        return app
    }

    /// A screen by its route's identifier ("screen.today"), whatever its type.
    func screen(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// One of the dock's buttons: "today", "inbox", "lists" or "capture".
    func dock(_ item: String) -> XCUIElement {
        buttons["dock.\(item)"]
    }

    /// Waits for `identifier`'s screen, failing the test with its name if it
    /// never appears.
    @discardableResult
    func waitForScreen(_ identifier: String, timeout: TimeInterval = 10,
                       file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = screen(identifier)
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(identifier) did not appear", file: file, line: line)
        return element
    }

    /// Waits until `identifier`'s screen has gone.
    func waitForScreenToClose(_ identifier: String, timeout: TimeInterval = 10,
                              file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: screen(identifier))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: timeout), .completed, "\(identifier) is still open",
                       file: file, line: line)
    }
}
