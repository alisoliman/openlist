//
//  WidgetsUITests.swift
//  OpenlistiOSUITests
//

import XCTest
import Vision

/// The widgets and the work Live Activity (mockup 05), outside the app: the
/// Dynamic Island while work runs, the Lock Screen presentation in
/// Notification Center, and the widget gallery's Openlist widgets. SpringBoard
/// is driven by what it shows, so each step is saved for review
/// (`OPENLIST_SHOTS_DIR`, as `ScreensUITests`).
final class WidgetsUITests: XCTestCase {
    @MainActor private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }
    @MainActor private var posterboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.PosterBoard") }

    override func setUp() {
        continueAfterFailure = true
    }

    /// On the system clock, as the Lock Screen's buttons stamp their taps:
    /// a pinned clock would find them from days ahead.
    @MainActor
    func testWorkLiveActivity() throws {
        let app = XCUIApplication.reviewSession(now: nil)
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)
        sleep(2)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        sleep(2)
        snap("island-compact")

        // Held, the island opens to the expanded presentation.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.028)).press(forDuration: 1.2)
        sleep(2)
        snap("island-expanded")
        let expandedPause = springboard.buttons["Pause"]
        XCTAssertTrue(expandedPause.waitForExistence(timeout: 3), "The expanded island has Pause")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        sleep(1)

        // Notification Center draws the Lock Screen presentation.
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.002))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75)))
        sleep(2)
        snap("lock-live-activity")
        XCTAssertTrue(springboard.buttons["Done"].waitForExistence(timeout: 3), "The Lock Screen activity has Done")

        // The first activity asks once whether Openlist may show them; the
        // card moves down as the question goes, so let it settle.
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) {
            allow.tap()
            sleep(3)
        }
        // Pause from the activity acts in the app, and the activity follows.
        // The system can take a while to run the first intent on a loaded
        // machine (19 s was seen on CI), so each step waits up to a minute.
        springboard.buttons["Pause"].firstMatch.tap()
        XCTAssertTrue(springboard.buttons["Resume"].waitForExistence(timeout: 60), "Pause from the activity pauses the work")
        snap("lock-live-activity-paused")
        springboard.buttons["Resume"].firstMatch.tap()
        XCTAssertTrue(springboard.buttons["Pause"].waitForExistence(timeout: 60))
        // Done completes the task in the app, and the activity goes.
        springboard.buttons["Done"].firstMatch.tap()
        let ended = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                              object: springboard.buttons["Pause"])
        XCTAssertEqual(XCTWaiter().wait(for: [ended], timeout: 60), .completed, "Done from the activity ends it")
        snap("lock-live-activity-done")
        let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995))
        bottom.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        sleep(1)
    }

    /// The widget gallery's Openlist widgets, with the sample the gallery previews.
    @MainActor
    func testWidgetGallery() throws {
        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        sleep(1)
        // An empty spot on the Home Screen: a long press starts editing.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).press(forDuration: 1.6)
        sleep(1)
        snap("home-editing")
        let edit = springboard.buttons["Edit"]
        if edit.waitForExistence(timeout: 3) {
            edit.tap()
            sleep(1)
            let add = springboard.buttons["Add Widget"].exists ? springboard.buttons["Add Widget"] : springboard.buttons["Add Widgets"]
            if add.waitForExistence(timeout: 3) { add.tap() }
        } else if springboard.buttons["Add Widget"].exists {
            springboard.buttons["Add Widget"].tap()
        }
        sleep(2)
        snap("gallery")
        let search = springboard.searchFields.firstMatch
        guard search.waitForExistence(timeout: 5) else {
            XCTFail("The Home Screen widget gallery did not open. \(springboard.debugDescription)")
            return
        }
        search.tap()
        search.typeText("Openlist")
        sleep(2)
        snap("gallery-search")
        try requireNamedElement("Openlist", in: [springboard]).tap()
        // Previews draw a moment after each page settles.
        sleep(4)
        XCTAssertTrue(springboard.staticTexts["Today"].firstMatch.waitForExistence(timeout: 5))
        try requireNamedElement("Add Widget", in: [springboard])
        try assertRenderedText(["Today", "2 of 12 done"])
        snap("gallery-openlist-1")
        // Each page of the gallery is one widget and size.
        for page in 2...3 {
            springboard.swipeLeft()
            sleep(4)
            XCTAssertTrue(springboard.staticTexts[page == 3 ? "Inbox" : "Today"].firstMatch.exists)
            try requireNamedElement("Add Widget", in: [springboard])
            try assertRenderedText(page == 3 ? ["Inbox", "6", "to triage", "Capture"] : ["Today", "open", "overdue"])
            snap("gallery-openlist-\(page)")
        }
    }

    /// The Lock Screen's Openlist widgets: the Today ring and Up next, from
    /// the Lock Screen's own gallery, reached from the cover sheet.
    @MainActor
    func testLockScreenWidgetGallery() throws {
        let previewStartedAt = Date()
        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 45)
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        sleep(1)
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.002))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75)))
        sleep(2)
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).press(forDuration: 1.6)
        sleep(2)
        snap("lock-customize")
        for title in ["Customize", "Lock Screen"] {
            let button = springboard.buttons[title]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                sleep(2)
                snap("lock-customize-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))")
            }
        }
        // PosterBoard exposes the visible ADD WIDGETS row by this identifier,
        // but its duplicate remote accessibility elements can report that
        // they are not hittable. Only use the observed row's center after
        // checking that its whole frame is on screen.
        let lockApps = [posterboard, springboard]
        let addWidgets = posterboard.buttons.matching(identifier: "grouped-widgets-reticle-view").firstMatch
        guard addWidgets.waitForExistence(timeout: 20) else {
            snap("lock-missing-add-widgets")
            XCTFail("The Lock Screen editor must expose its widget row. \(posterboard.debugDescription)")
            return
        }
        let widgetFrame = addWidgets.frame
        guard widgetFrame.width > 0, widgetFrame.height > 0,
              springboard.frame.contains(widgetFrame) else {
            snap("lock-add-widgets-offscreen")
            XCTFail("The widget row must be fully on screen before tapping: \(widgetFrame)")
            return
        }
        snap("lock-add-widgets-before-tap")
        if addWidgets.isHittable {
            addWidgets.tap()
        } else {
            addWidgets.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        sleep(2)
        snap("lock-gallery")
        var openlist = namedElement("Openlist", in: lockApps)
        for _ in 0..<4 where openlist == nil {
            posterboard.swipeUp()
            sleep(1)
            openlist = namedElement("Openlist", in: lockApps)
        }
        snap("lock-gallery-scrolled")
        try XCTUnwrap(openlist, "Openlist must be present in the Lock Screen widget gallery. \(posterboard.debugDescription)").tap()
        sleep(2)
        try requireNamedElement("Openlist", in: lockApps)
        try assertRenderedText(["Today", "2/12"])
        snap("lock-gallery-openlist")
        // There are two Lock Screen pages: Today, then Up next.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.73))
            .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.73)))
        sleep(1)
        // The widget extension uses its own real clock; the app's pinned
        // review clock does not reach the gallery. Require the exact sample
        // title for that time, allowing a transition while the preview loads.
        let expectedTitles = Set([
            lockScreenPreviewTitle(at: previewStartedAt),
            lockScreenPreviewTitle(at: Date()),
            lockScreenPreviewTitle(at: Date().addingTimeInterval(20)),
        ])
        try assertRenderedText(["Up next"], anyOf: Array(expectedTitles))
        snap("lock-gallery-openlist-2")
    }

    // MARK: Helpers

    @MainActor
    private func namedElement(_ label: String, in apps: [XCUIApplication]) -> XCUIElement? {
        // The Home Screen gallery prefixes Add Widget with a space.
        let labelPattern = "\\s*" + NSRegularExpression.escapedPattern(for: label) + "\\s*"
        for app in apps {
            let matches = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES[c] %@", labelPattern))
            if let element = matches.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
                return element
            }
        }
        return nil
    }

    @MainActor
    @discardableResult
    private func requireNamedElement(_ label: String, in apps: [XCUIApplication], timeout: TimeInterval = 10) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = namedElement(label, in: apps) { return element }
            usleep(250_000)
        } while Date() < deadline
        snap("widget-missing-\(label.lowercased().replacingOccurrences(of: " ", with: "-"))")
        return try XCTUnwrap(nil as XCUIElement?, "Missing visible \(label). \(apps.map(\.debugDescription).joined(separator: "\n"))")
    }

    @MainActor
    private func assertRenderedText(_ expected: [String], anyOf alternatives: [String] = [], timeout: TimeInterval = 20,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var recognized = ""
        repeat {
            let pixels = try XCTUnwrap(XCUIScreen.main.screenshot().image.cgImage,
                                      "The widget screenshot must contain pixels", file: file, line: line)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: pixels).perform([request])
            recognized = normalizeText((request.results ?? []).compactMap {
                $0.topCandidates(1).first?.string
            }.joined(separator: " "))
            func contains(_ text: String) -> Bool {
                (" " + recognized + " ").contains(" " + normalizeText(text) + " ")
            }
            if expected.allSatisfy(contains) && (alternatives.isEmpty || alternatives.contains(where: contains)) {
                return
            }
            usleep(500_000)
        } while Date() < deadline
        XCTFail("Expected rendered widget text \(expected), one of \(alternatives). Recognized: \(recognized)", file: file, line: line)
    }

    /// Expected Lock Screen sample across the day. While a task is under
    /// way this widget names what follows it, including the 14:00 meeting;
    /// after the last task ends it must show the empty state.
    private func lockScreenPreviewTitle(at date: Date) -> String {
        let clock = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = (clock.hour ?? 0) * 60 + (clock.minute ?? 0)
        switch minute {
        case ..<600: return "Draft Q3 OKRs"
        case ..<690: return "Write interview feedback for Priya"
        case ..<780: return "Update the design role scorecard"
        case ..<810: return "Board prep"
        case ..<990: return "Order new water filters"
        case ..<1095: return "Pay the ryokan deposit"
        default: return "Nothing else planned"
        }
    }

    private func normalizeText(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "\\s*/\\s*", with: "/", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    @MainActor
    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
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
