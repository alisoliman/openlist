//
//  IPadShellUITests.swift
//  OpenlistiOSUITests
//

import UIKit
import XCTest

@MainActor
final class IPadShellUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSidebarFindFromTodayAndInbox() throws {
        try requireIPad()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)
        let find = sidebar("find", in: app)
        find.tap()
        app.waitForScreen("screen.find")
        XCTAssertTrue(find.isSelected)
        sidebar("inbox", in: app).tap()
        app.waitForScreen("screen.inbox")
        find.tap()
        app.waitForScreen("screen.find")
        XCTAssertTrue(find.isSelected)
    }

    func testBaselineFindInteractiveBackDiagnostic() throws {
        try requireIPad()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)
        sidebar("find", in: app).tap()
        let find = app.waitForScreen("screen.find")
        let sidebarFrame = app.descendants(matching: .any)["ipad.sidebar"].frame
        print("SWIPE_GEOMETRY app=\(app.frame) sidebar=\(sidebarFrame) find=\(find.frame)")
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "find-before-swipe"
        before.lifetime = .keepAlways
        add(before)
        let edge = find.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 2, dy: 0))
        edge.press(forDuration: 0.1, thenDragTo: edge.withOffset(CGVector(dx: 500, dy: 0)),
                   withVelocity: XCUIGestureVelocity(rawValue: 1200), thenHoldForDuration: 0)
        let swipedBack = app.screen("screen.lists").waitForExistence(timeout: 10)
        print("SWIPE_RESULT back=\(swipedBack) hierarchy=\(app.debugDescription)")
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "find-after-swipe"
        after.lifetime = .keepAlways
        add(after)
        if !swipedBack {
            app.buttons["Back to Lists"].tap()
            app.waitForScreen("screen.lists")
        }
        XCTAssertTrue(swipedBack, "Interactive Back did not return to Lists")
    }

    func testSidebarAndDetailAreBothUsableInLandscape() throws {
        try requireIPad()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)

        let inbox = sidebar("inbox", in: app)
        let todayTask = app.buttons["Close out Q2 retro actions"]
        XCTAssertTrue(inbox.isHittable)
        XCTAssertTrue(todayTask.isHittable)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertLessThanOrEqual(inbox.frame.maxX, todayTask.frame.minX, "The sidebar and Today occupy separate columns")
        XCTAssertFalse(app.dock("today").exists)

        inbox.tap()
        app.waitForScreen("screen.inbox")
        XCTAssertTrue(inbox.isSelected)
        XCTAssertFalse(sidebar("today", in: app).isSelected)
        sidebar("work", in: app).tap()
        app.waitForScreen("screen.work")
        sidebar("lists", in: app).tap()
        app.waitForScreen("screen.lists")
        sidebar("find", in: app).tap()
        app.waitForScreen("screen.find")
        XCTAssertTrue(sidebar("find", in: app).isSelected)

        sidebar("settings", in: app).tap()
        app.waitForScreen("screen.settings")
        app.buttons["settings.done"].tap()
        XCTAssertTrue(sidebar("find", in: app).wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertTrue(sidebar("find", in: app).isSelected)
    }

    func testListShortcutOpensTaskDetailAndKeepsCaptureInThatList() throws {
        try requireIPad()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication.reviewSession()
        app.launch()
        app.waitForScreen("screen.today", timeout: 20)

        let list = listShortcut("Weekend in Kyoto", in: app)
        XCTAssertTrue(list.isHittable)
        list.tap()
        app.waitForScreen("screen.list")
        XCTAssertTrue(list.isSelected)
        app.buttons["Renew passports"].tap()
        app.waitForScreen("screen.taskDetail")
        XCTAssertTrue(list.isHittable)
        XCTAssertTrue(list.isSelected)
        XCTAssertTrue(sidebar("capture", in: app).isHittable)
        XCTAssertEqual(app.textFields["detail.title"].value as? String, "Renew passports")
        app.buttons["Back to Weekend in Kyoto"].tap()
        app.waitForScreen("screen.list")

        sidebar("capture", in: app).tap()
        let capture = app.waitForScreen("screen.capture")
        let destination = capture.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Weekend in Kyoto")).firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        XCTAssertTrue(destination.isSelected)
        capture.buttons["Cancel"].tap()
        XCTAssertTrue(list.wait(for: \.isHittable, toEqual: true, timeout: 5))
        XCTAssertTrue(list.isSelected)
    }

    func testRotatingKeepsTheListAndTaskOpenedAtLaunch() throws {
        try requireIPad()
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": "task:Renew passports"])
        app.launch()
        app.waitForScreen("screen.taskDetail", timeout: 20)
        XCTAssertLessThan(app.frame.width, app.frame.height)

        XCUIDevice.shared.orientation = .landscapeLeft
        let list = listShortcut("Weekend in Kyoto", in: app)
        XCTAssertTrue(list.wait(for: \.isHittable, toEqual: true, timeout: 10))
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertTrue(list.isSelected)
        XCTAssertEqual(app.textFields["detail.title"].value as? String, "Renew passports")
        app.buttons["Back to Weekend in Kyoto"].tap()
        app.waitForScreen("screen.list")
    }

    private func requireIPad() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "The sidebar is an iPad layout")
    }

    private func sidebar(_ item: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "sidebar.\(item)").firstMatch
    }

    private func listShortcut(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                                                               "sidebar.list.", title)).firstMatch
    }
}
