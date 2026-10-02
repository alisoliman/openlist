//
//  PaperAppearanceUITests.swift
//  OpenlistiOSUITests
//

import XCTest

/// Captures the complete paper-style journey in a seeded, local-only library.
/// Attachments are for visual comparison; the assertions verify that the
/// photographed screens and their essential controls remain usable.
final class PaperAppearanceUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLightAppearanceAcrossTheJourney() {
        let app = makeApp(appearance: "light")
        open("today", screen: "today", in: app)
        XCTAssertTrue(app.screen("today.progress").exists)
        XCTAssertTrue(app.buttons["today.settings"].isHittable)
        snapshot(app, "paper-light-today-top")
        XCTAssertTrue(app.dock("capture").isHittable)
        XCTAssertEqual(app.frame.maxY - app.dock("capture").frame.maxY, 28, accuracy: 2,
                       "The capture dock floats 28 points above the screen edge on every iPhone")
        reveal(app.buttons["today.add"], in: app)
        XCTAssertTrue(app.buttons["today.done"].exists)
        snapshot(app, "paper-light-today-lower")

        for (route, screen, name) in [
            ("inbox", "inbox", "inbox"),
            ("lists", "lists", "lists-cards"),
            ("work", "work", "work"),
            ("list:Weekend in Kyoto", "list", "list-document"),
            ("task:Book the ryokan", "taskDetail", "task-detail"),
            ("settings", "settings", "settings"),
        ] {
            open(route, screen: screen, in: app)
            snapshot(app, "paper-light-\(name)")
            if route == "task:Book the ryokan" {
                let start = app.buttons["detail.start"]
                XCTAssertTrue(start.isHittable)
                XCTAssertEqual(app.frame.maxY - start.frame.maxY, 28, accuracy: 2,
                               "The task action dock floats 28 points above the screen edge on every iPhone")
            }
            if route == "lists" {
                app.buttons["lists.view.tasks"].tap()
                XCTAssertTrue(app.buttons["lists.filter"].isHittable)
                snapshot(app, "paper-light-lists-tasks")
                app.buttons["lists.view.cards"].tap()
            }
            if route == "settings" {
                reveal(app.buttons["settings.swipe.first"], in: app)
                XCTAssertTrue(app.buttons["settings.swipe.second"].exists)
                snapshot(app, "paper-light-settings-swipes")
            }
        }
    }

    @MainActor
    func testDarkAppearanceAndReduceMotionActions() {
        let app = makeApp(appearance: "dark")
        for (route, screen) in [("today", "today"), ("inbox", "inbox"), ("lists", "lists"),
                                ("work", "work"), ("task:Book the ryokan", "taskDetail"), ("settings", "settings")] {
            open(route, screen: screen, in: app)
            snapshot(app, "paper-dark-\(screen)")
            if route == "lists" {
                app.buttons["lists.view.tasks"].tap()
                XCTAssertTrue(app.buttons["lists.filter"].isHittable)
                snapshot(app, "paper-dark-lists-tasks")
            }
        }
        let motion = app.switches["settings.reduceMotion"]
        reveal(motion, in: app)
        if motion.value as? String != "1" { motion.tap() }
        XCTAssertEqual(motion.value as? String, "1")
        snapshot(app, "paper-dark-reduce-motion-setting")
        app.buttons["settings.done"].tap()
        app.waitForScreenToClose("screen.settings")
        app.dock("today").tap()
        app.waitForScreen("screen.today")
        let complete = app.buttons["Complete Fix the dripping bathroom tap"]
        reveal(complete, in: app)
        complete.tap()
        XCTAssertTrue(app.buttons["tray.action"].waitForExistence(timeout: 5))
        snapshot(app, "paper-dark-reduce-motion-undo")
        app.buttons["tray.action"].tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        app.dock("work").tap()
        app.waitForScreen("screen.work")
        XCTAssertTrue(app.dock("work").isSelected)
    }

    @MainActor
    func testAccessibilityXXXLKeepsEssentialControlsReachable() {
        let app = makeApp(appearance: "light", largeType: true)
        open("today", screen: "today", in: app)
        let date = app.staticTexts[XCUIApplication.fixtureDay(23)]
        XCTAssertGreaterThan(date.frame.height, 35, "The accessibility XXXL launch argument must enlarge the date; default-size captures do not verify large text")
        XCTAssertTrue(app.buttons["today.settings"].isHittable)
        snapshot(app, "paper-xxxl-today-top")
        let add = app.buttons["today.add"]
        reveal(add, in: app)
        assertHorizontallyContained(add, in: app)
        snapshot(app, "paper-xxxl-today-lower")
        add.tap()
        app.waitForScreen("screen.capture")
        XCTAssertTrue(app.textFields["capture.field"].waitForExistence(timeout: 5))
        snapshot(app, "paper-xxxl-capture-open")
        app.buttons["Cancel"].tap()
        app.waitForScreenToClose("screen.capture")

        for (route, screen, name) in [
            ("inbox", "inbox", "inbox"),
            ("lists", "lists", "lists-cards"),
            ("work", "work", "work"),
            ("list:Weekend in Kyoto", "list", "list-document"),
            ("task:Book the ryokan", "taskDetail", "task-detail"),
            ("settings", "settings", "settings"),
        ] {
            open(route, screen: screen, in: app)
            snapshot(app, "paper-xxxl-\(name)")
            if route == "lists" {
                let tasks = app.buttons["lists.view.tasks"]
                reveal(tasks, in: app)
                assertHorizontallyContained(tasks, in: app)
                tasks.tap()
                let filter = app.buttons["lists.filter"]
                reveal(filter, in: app)
                assertHorizontallyContained(filter, in: app)
                snapshot(app, "paper-xxxl-lists-tasks")
                filter.tap()
                XCTAssertTrue(app.buttons["lists.filter.all"].waitForExistence(timeout: 5))
                app.buttons["lists.filter.all"].tap()
            }
            if route == "task:Book the ryokan" {
                let start = app.buttons["detail.start"]
                XCTAssertTrue(start.waitForExistence(timeout: 5))
                XCTAssertEqual(start.label, "Start working")
                XCTAssertTrue(start.isHittable)
                assertHorizontallyContained(start, in: app)
                XCTAssertGreaterThanOrEqual(start.frame.minY, app.frame.minY)
                XCTAssertLessThanOrEqual(start.frame.maxY, app.frame.maxY)
                start.tap()
                app.waitForScreen("screen.working")
                XCTAssertTrue(app.staticTexts["Book the ryokan"].waitForExistence(timeout: 5))
                let pause = app.buttons["working.pause"]
                reveal(pause, in: app)
                XCTAssertEqual(pause.label, "Pause")
                XCTAssertTrue(pause.isHittable)
                assertHorizontallyContained(pause, in: app)
                snapshot(app, "paper-xxxl-working")
                pause.tap()
                XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
                XCTAssertEqual(pause.label, "Resume")
                XCTAssertTrue(pause.isHittable)
                let next = app.buttons["working.next"]
                reveal(next, in: app)
                XCTAssertEqual(next.label, "Next, Write interview feedback for Priya, 11:30")
                assertHorizontallyContained(next, in: app)
                snapshot(app, "paper-xxxl-working-next")
                next.tap()
                app.waitForScreen("screen.taskDetail")
                XCTAssertEqual(app.textFields["detail.title"].value as? String, "Write interview feedback for Priya")
            }
            if route == "settings" {
                let first = app.buttons["settings.swipe.first"]
                reveal(first, in: app)
                assertHorizontallyContained(first, in: app)
                snapshot(app, "paper-xxxl-settings-swipes")
                first.tap()
                XCTAssertTrue(app.buttons["Tomorrow"].waitForExistence(timeout: 5))
                app.buttons["Tomorrow"].tap()
                XCTAssertTrue(first.label.contains("Tomorrow"))
            }
        }
    }

    @MainActor
    private func makeApp(appearance: String, largeType: Bool = false) -> XCUIApplication {
        let app = XCUIApplication.reviewSession()
        // Foundation's launch-argument domain also applies to the review
        // defaults suite, so the production preference selects the scheme.
        app.launchArguments += ["-settings.appearance", appearance]
        if largeType {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        return app
    }

    @MainActor
    private func open(_ route: String, screen: String, in app: XCUIApplication) {
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launchEnvironment["OpenlistOpenRoute"] = route
        app.launch()
        app.waitForScreen("screen.\(screen)", timeout: 45)
        if route == "today" {
            let seeded = app.staticTexts[XCUIApplication.fixtureDay(23)].waitForExistence(timeout: 10)
            if !seeded { snapshot(app, "paper-invalid-fixture-launch") }
            XCTAssertTrue(seeded, "The visual review must use the pinned fixture date. \(app.debugDescription)")
            XCTAssertEqual(app.screen("today.progress").value as? String, "2 of 13 done", "Visual review requires the seeded tasks, not an empty library")
            XCTAssertTrue(app.buttons["Complete Close out Q2 retro actions"].exists)
        }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        // Accessibility can report a partially visible row as hittable even
        // when its tap point is under the floating dock. Reveal the whole
        // control before touching it, as a person scrolling the page would.
        func isFullyVisible() -> Bool {
            guard element.exists, element.isHittable else { return false }
            let frame = element.frame
            var viewport = app.frame
            let dock = app.dock("capture")
            if dock.exists {
                viewport.size.height = min(viewport.maxY, dock.frame.minY) - viewport.minY
            }
            return !frame.isEmpty && viewport.contains(frame)
        }
        for _ in 0..<18 where !isFullyVisible() { app.swipeUp() }
        XCTAssertTrue(isFullyVisible(), "The whole control must be visible above the dock before tapping: \(element.frame)")
    }

    @MainActor
    private func assertHorizontallyContained(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX - 1)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX + 1)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        usleep(350_000)
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
