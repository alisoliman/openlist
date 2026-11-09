//
//  ReviewLaunch.swift
//  OpenlistiOSUITests
//

import Foundation
import XCTest

@MainActor
private enum ReviewLaunchState {
    static var hasResolvedInitialProcess = false
}

extension XCUIApplication {
    /// The mockups' moment, which the app's fixture is written for
    /// (OpenlistiOS/Fixtures/PhoneFixture.swift).
    static let mockupNow = "2026-09-23T10:40:00"

    /// A day of September 2026 as Today's eyebrow and Activity name it, in
    /// the device's own order: "Wednesday 23 September", or "Wednesday,
    /// September 23" (`OLFormat.eyebrowDate`).
    static func fixtureDay(_ day: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 12))!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: date)
    }

    /// The app in a fresh review session: its own store, media and defaults,
    /// iCloud off, no system notifications, and the iPhone fixture seeded
    /// (Shared/ReviewSession.swift reads the variable in Debug builds only).
    /// `now`, an ISO 8601 date, pins the fixture's clock. The tray keeps each
    /// message until it's dismissed or replaced (`OpenlistTraysStay`), as a
    /// loaded simulator can take longer than a message's seconds to reach it.
    static func reviewSession(now: String? = mockupNow, environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        // A new runner can initially report a stale .notRunning state for
        // the target Xcode prepared. Explicitly end it before configuring
        // this launch, so fixture variables and Dynamic Type arguments apply.
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "The previous app instance must end before configuring a review session")
        var variables = ["OpenlistReviewSession": "UITest-\(UUID().uuidString)", "OpenlistTraysStay": "1"]
        if let now { variables["OpenlistFixtureNow"] = now }
        variables.merge(environment) { _, supplied in supplied }
        app.launchEnvironment = variables
        if !ReviewLaunchState.hasResolvedInitialProcess {
            // Xcode can leave its prepared app running while a fresh UI
            // runner reports PID 0. The first launch resolves that process
            // but may only activate it, ignoring this session's environment.
            // Once its PID is known, terminate it so the caller's launch
            // applies the fixture, route and any accessibility arguments.
            app.launch()
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
            ReviewLaunchState.hasResolvedInitialProcess = true
        }
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

    /// Puts the tray's message away with a swipe down, as a person would
    /// when it covers what they want next: in UI tests a message stays until
    /// it's dismissed (`OpenlistTraysStay`).
    func dismissTray(file: StaticString = #filePath, line: UInt = #line) {
        // The tray is an "Other"; the dock's Inbox symbol is named "tray" too.
        let trays = otherElements.matching(identifier: "tray")
        guard let tray = trays.allElementsBoundByIndex.last(where: \.isHittable) else {
            return XCTFail("No tray message to put away", file: file, line: line)
        }
        let start = tray.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 80)))
        XCTAssertTrue(trays.firstMatch.waitForNonExistence(timeout: 5), "The tray's message is still up", file: file, line: line)
    }
}
