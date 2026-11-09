//
//  TodayScheduleUITests.swift
//  OpenlistiOSUITests
//

import XCTest

/// Today's Now card and the Timeline in the Mac's look: what's on now and
/// next, meetings included, a meeting's details on a long press, Fit for the
/// tasks with no time yet, the quiet empty and no-calendar states, the card
/// folded to one line, and a block's checkbox. With `OPENLIST_SHOTS_DIR` in the runner's environment
/// (`TEST_RUNNER_OPENLIST_SHOTS_DIR` through xcodebuild) each state is saved
/// there, in the appearance `OPENLIST_SHOTS_APPEARANCE` names (light unless
/// it says dark).
final class TodayScheduleUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// The running work leads, what's next follows with its list, and the
    /// Timeline draws the day as the Mac does; a block's checkbox ticks its
    /// task, and Fit gives today's tasks with no time a slot.
    @MainActor
    func testTheNowCardTheTimelineAndFit() {
        let app = launch()
        let now = app.buttons["today.schedule.now"]
        XCTAssertTrue(now.waitForExistence(timeout: 10))
        XCTAssertEqual(now.label, "Now: Draft Q3 OKRs")
        XCTAssertTrue((now.value as? String)?.hasPrefix("Working · ") == true, "\(String(describing: now.value))")
        XCTAssertTrue(app.buttons["Open Working"].exists)
        let next = app.buttons["today.schedule.next"]
        XCTAssertEqual(next.label, "Next: Write interview feedback for Priya")
        let detail = next.value as? String ?? ""
        XCTAssertTrue(detail.hasPrefix("11:30 · in ") && detail.hasSuffix(" · Hiring loop"), detail)
        XCTAssertTrue(app.staticTexts["4 tasks have no time yet"].exists)
        XCTAssertFalse(app.buttons["today.connect"].exists, "The fixture's calendar counts as connected")
        snap(app, "today-running-work")

        app.buttons["today.timeline"].tap()
        app.waitForScreen("screen.timeline")
        XCTAssertTrue(app.element(beginningWith: "Design sync, meeting, 14:00 to 15:00, Studio, 3rd floor").exists)
        XCTAssertTrue(app.element(beginningWith: "Team standup, meeting, 09:30 to 09:45").exists)
        let priya = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Write interview feedback for Priya, 11:30 to 11:50, next'"))
            .firstMatch
        XCTAssertTrue(priya.exists)
        snap(app, "timeline")
        // The checkbox at the block's start ticks it, with Undo.
        priya.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 14, dy: 0)).tap()
        let tray = app.screen("tray")
        XCTAssertTrue(tray.waitForExistence(timeout: 5))
        XCTAssertTrue(tray.staticTexts["Completed “Write interview feedback for Priya”"].exists)
        app.buttons["tray.action"].tap()
        app.buttons["timeline.list"].tap()
        app.waitForScreen("screen.today")

        let fit = app.buttons["today.fit"]
        XCTAssertTrue(fit.waitForExistence(timeout: 5))
        fit.tap()
        XCTAssertTrue(app.screen("tray").staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Planned '"))
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(fit.waitForNonExistence(timeout: 5), "Fitted, the tasks have their time")
        snap(app, "today-fitted")
    }

    /// A meeting comes next, with its place; a long press shows its details,
    /// on Today and on the Timeline, where slots gone by are missed.
    @MainActor
    func testAMeetingsDetailsOnALongPress() {
        let app = launch(now: "2026-09-23T13:50:00")
        let next = app.descendants(matching: .any)["today.schedule.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertEqual(next.label, "Next: Design sync")
        XCTAssertTrue((next.value as? String)?.contains("Studio, 3rd floor") == true)
        snap(app, "today-meeting-next")
        next.press(forDuration: 1.2)
        let show = app.buttons["Show in Timeline"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open in Calendar"].exists)
        snap(app, "today-meeting-preview")
        show.tap()
        app.waitForScreen("screen.timeline")
        let meeting = app.element(beginningWith: "Design sync, meeting, 14:00 to 15:00")
        XCTAssertTrue(meeting.waitForExistence(timeout: 5))
        XCTAssertTrue(app.element(beginningWith: "Write interview feedback for Priya, missed, carried forward").exists)
        snap(app, "timeline-missed-and-meetings")
        meeting.press(forDuration: 1.2)
        let open = app.buttons["Open in Calendar"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        snap(app, "timeline-meeting-preview")
        // Away from the menu and its preview (the week strip), so it closes
        // without leaving the app.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)).tap()
        XCTAssertTrue(open.waitForNonExistence(timeout: 5))
    }

    /// A meeting under way is now beside the work, and the next session follows.
    @MainActor
    func testAMeetingUnderWayIsNowToo() {
        let app = launch(now: "2026-09-23T14:20:00")
        let meeting = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Also now: Design sync'")).firstMatch
        XCTAssertTrue(meeting.waitForExistence(timeout: 10))
        XCTAssertTrue((meeting.value as? String)?.hasPrefix("Until 15:00 · Studio, 3rd floor") == true)
        XCTAssertEqual(app.buttons["today.schedule.next"].label, "Next: Order new water filters")
        snap(app, "today-meeting-now")
    }

    /// With the work done, the slot on now is the work to start, and a
    /// meeting is next.
    @MainActor
    func testASlotOnNowOffersStart() {
        let app = launch(now: "2026-09-23T13:15:00", route: "working")
        finishTheWork(in: app)
        let now = app.buttons["today.schedule.now"]
        XCTAssertTrue(now.waitForExistence(timeout: 10))
        XCTAssertEqual(now.label, "Now: Update the design role scorecard")
        XCTAssertTrue((now.value as? String)?.hasPrefix("Until 13:30") == true)
        XCTAssertTrue(app.buttons["Start working"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["today.schedule.next"].label, "Next: Design sync")
        snap(app, "today-now-and-next")
    }

    /// Once the day's work is done, the card says nothing else is on, and
    /// still offers to fit today's tasks. Folded, its one line says so.
    @MainActor
    func testNothingElseToday() {
        let app = launch(now: "2026-09-23T21:30:00", route: "working", environment: ["OpenlistReviewMeetings": "none"])
        finishTheWork(in: app)
        XCTAssertTrue(app.staticTexts["Nothing else scheduled today."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["today.schedule.now"].exists)
        XCTAssertTrue(app.buttons["today.fit"].exists)
        snap(app, "today-empty")

        app.buttons["today.schedule.fold"].tap()
        let summary = app.buttons["today.schedule.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "Nothing else scheduled today.")
        XCTAssertTrue(app.buttons["today.fit"].waitForNonExistence(timeout: 5), "Folded, the card's notes go")
        snap(app, "today-empty-folded")
    }

    /// The chevron folds the card to one line, what's on now and when; it
    /// stays folded through a relaunch, and a tap on the line opens it
    /// again. A meeting held online names its service, not its link.
    @MainActor
    func testTheCardFoldsToOneLineAndStaysFolded() {
        // One session for both launches: its store and its preferences.
        let environment = ["OpenlistReviewMeetings": "links", "OpenlistReviewSession": "UITest-\(UUID().uuidString)"]
        let app = launch(now: "2026-09-23T13:50:00", environment: environment)
        let next = app.descendants(matching: .any)["today.schedule.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertEqual(next.label, "Next: Design sync")
        let detail = next.value as? String ?? ""
        XCTAssertTrue(detail.hasPrefix("14:00 · in 10 min · Microsoft Teams") && !detail.contains("https:"), detail)
        let fold = app.buttons["today.schedule.fold"]
        XCTAssertEqual(fold.label, "Schedule")
        XCTAssertEqual(fold.value as? String, "Expanded")
        snap(app, "today-open-online")

        fold.tap()
        let summary = app.buttons["today.schedule.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "Now: Draft Q3 OKRs")
        XCTAssertTrue(next.waitForNonExistence(timeout: 5), "Folded, the card shows its first line alone")
        XCTAssertEqual(fold.value as? String, "Collapsed")
        snap(app, "today-folded")

        let again = launch(now: "2026-09-23T13:50:00", environment: environment)
        let kept = again.buttons["today.schedule.summary"]
        XCTAssertTrue(kept.waitForExistence(timeout: 10), "Folded it stays, through a relaunch")
        XCTAssertFalse(again.descendants(matching: .any)["today.schedule.next"].exists)
        snap(again, "today-folded-relaunched")

        kept.tap()
        XCTAssertTrue(again.descendants(matching: .any)["today.schedule.next"].waitForExistence(timeout: 5))
        XCTAssertEqual(again.buttons["today.schedule.fold"].value as? String, "Expanded")
        XCTAssertFalse(kept.exists)
        snap(again, "today-opened-again")
    }

    /// No calendar connected: a quiet line offers Connect. It's never tapped
    /// here, as it asks for access.
    @MainActor
    func testNoCalendarConnected() {
        let app = launch(environment: ["OpenlistReviewMeetings": "NO"])
        let connect = app.buttons["today.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        XCTAssertEqual(connect.label, "Connect")
        XCTAssertTrue(app.staticTexts["No calendar connected"].exists)
        XCTAssertEqual(app.buttons["today.schedule.next"].label, "Next: Write interview feedback for Priya")
        snap(app, "today-no-calendar")
    }

    // MARK: Helpers

    /// Working's Done, then back on Today.
    @MainActor
    private func finishTheWork(in app: XCUIApplication) {
        app.waitForScreen("screen.working", timeout: 45)
        app.buttons["working.done"].tap()
        app.waitForScreenToClose("screen.working")
        app.waitForScreen("screen.today")
    }

    private var appearance: String {
        ProcessInfo.processInfo.environment["OPENLIST_SHOTS_APPEARANCE"] == "dark" ? "dark" : "light"
    }

    @MainActor
    private func launch(now: String = XCUIApplication.mockupNow, route: String? = nil,
                        environment: [String: String] = [:]) -> XCUIApplication {
        var variables = environment
        if let route { variables["OpenlistOpenRoute"] = route }
        let app = XCUIApplication.reviewSession(now: now, environment: variables)
        app.launchArguments += ["-settings.appearance", appearance]
        app.launch()
        // The first launch after the simulator boots can be slow.
        if route == nil { app.waitForScreen("screen.today", timeout: 45) }
        return app
    }

    /// The screen now, attached to the test and, with a folder given, saved.
    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        // Let springs and the tray settle.
        usleep(800_000)
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "\(appearance)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["OPENLIST_SHOTS_DIR"], !folder.isEmpty {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(appearance)-\(name).png")
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url)
        }
    }
}
