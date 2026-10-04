import XCTest

@MainActor
final class VoiceCaptureUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testTapOpensOnlyAnEmptyTypedDraftWithKeyboard() {
        let app = launch()
        app.dock("capture").tap()
        app.waitForScreen("screen.capture")
        XCTAssertTrue(app.textFields["capture.field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["capture.voiceDone"].exists)
        XCTAssertFalse(app.screen("screen.capture").buttons["Add"].isEnabled)
        app.screen("screen.capture").buttons["Cancel"].tap()
        assertInboxCount("6 to triage", app: app)
    }

    func testLongPressStartsListeningAndReleaseDoesNotTapOrStop() {
        let app = launch()
        app.dock("capture").press(forDuration: 0.7)
        app.waitForScreen("screen.capture")
        XCTAssertTrue(app.buttons["capture.voiceDone"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["capture.voiceDone"].label, "Done")
        XCTAssertTrue(app.staticTexts["Listening · pause when you’re done"].exists)
        XCTAssertFalse(app.textFields["capture.field"].exists)
        XCTAssertFalse(app.buttons["Say Tasks"].exists)
        app.buttons["capture.voiceDone"].tap()
        XCTAssertTrue(app.textFields["capture.field"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["capture.field"].value as? String, "Water the ferns")
        app.screen("screen.capture").buttons["Cancel"].tap()
        app.waitForScreenToClose("screen.capture")
        assertInboxCount("6 to triage", app: app)
    }

    func testAutomaticSaveUsesNormalFeedbackAndUndo() {
        let app = launch(route: "settings", transcript: "Water the ferns\nBuy compost")
        chooseAutomaticSave(app)
        app.buttons["settings.done"].tap()
        app.waitForScreenToClose("screen.settings")
        assertInboxCount("6 to triage", app: app)
        app.dock("capture").press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["capture.voiceDone"].waitForExistence(timeout: 5))
        app.buttons["capture.voiceDone"].tap()
        app.waitForScreenToClose("screen.capture")
        XCTAssertTrue(app.staticTexts["8 to triage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Water the ferns"].exists)
        XCTAssertTrue(app.buttons["Buy compost"].exists)
        XCTAssertTrue(app.buttons["tray.action"].waitForExistence(timeout: 5))
        app.buttons["tray.action"].tap()
        XCTAssertTrue(app.staticTexts["6 to triage"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Water the ferns"].exists)
        XCTAssertFalse(app.buttons["Buy compost"].exists)
    }

    func testUndoToastDoesNotBlockImmediateTabChange() {
        let app = launch(route: "settings", transcript: "Water the ferns\nBuy compost")
        chooseAutomaticSave(app)
        app.buttons["settings.done"].tap()
        app.waitForScreenToClose("screen.settings")
        app.dock("capture").press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["capture.voiceDone"].waitForExistence(timeout: 5))
        app.buttons["capture.voiceDone"].tap()
        app.waitForScreenToClose("screen.capture")
        XCTAssertTrue(app.buttons["tray.action"].waitForExistence(timeout: 5))
        app.buttons["tray.action"].tap()
        // No delay: the outgoing toast must not catch the next dock tap.
        assertInboxCount("6 to triage", app: app)
        XCTAssertFalse(app.buttons["Water the ferns"].exists)
        XCTAssertFalse(app.buttons["Buy compost"].exists)
    }

    func testAutomaticSaveOneTaskOnlyOnce() {
        let app = launch(route: "settings")
        chooseAutomaticSave(app)
        app.buttons["settings.done"].tap()
        app.waitForScreenToClose("screen.settings")
        app.dock("capture").press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["capture.voiceDone"].waitForExistence(timeout: 5))
        app.buttons["capture.voiceDone"].tap()
        app.waitForScreenToClose("screen.capture")
        assertInboxCount("7 to triage", app: app)
        XCTAssertEqual(app.buttons.matching(identifier: "Water the ferns").count, 1)
        app.dock("capture").tap()
        XCTAssertTrue(app.textFields["capture.field"].waitForExistence(timeout: 5))
        app.screen("screen.capture").buttons["Cancel"].tap()
        app.waitForScreenToClose("screen.capture")
        XCTAssertTrue(app.staticTexts["7 to triage"].waitForExistence(timeout: 5))
    }

    func testReviewMultipleTasksDoesNotSaveBeforeAdd() {
        let app = launch(transcript: "Water the ferns\nBuy compost")
        app.dock("capture").press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["capture.voiceDone"].waitForExistence(timeout: 5))
        app.buttons["capture.voiceDone"].tap()
        XCTAssertTrue(app.screen("capture.heard").waitForExistence(timeout: 5))
        XCTAssertTrue(app.screen("screen.capture").buttons["Add 2"].isEnabled)
        app.screen("screen.capture").buttons["Cancel"].tap()
        assertInboxCount("6 to triage", app: app)
    }

    func testNoSpeechDoesNotSaveInAutomaticMode() {
        let app = launch(route: "settings", transcript: "")
        chooseAutomaticSave(app)
        app.buttons["settings.done"].tap()
        app.waitForScreenToClose("screen.settings")
        app.dock("capture").press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["capture.voiceDone"].waitForExistence(timeout: 5))
        app.buttons["capture.voiceDone"].tap()
        XCTAssertTrue(app.textFields["capture.field"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.screen("screen.capture").buttons["Add"].isEnabled)
        app.screen("screen.capture").buttons["Cancel"].tap()
        assertInboxCount("6 to triage", app: app)
    }

    func testAutomaticSaveSettingDoesNotSaveATypedDraft() {
        let app = launch(route: "settings")
        chooseAutomaticSave(app)
        app.buttons["settings.done"].tap()
        app.waitForScreenToClose("screen.settings")
        app.dock("capture").tap()
        let field = app.textFields["capture.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Keep typing this task")
        app.buttons["capture.voice"].tap()
        app.buttons["capture.voiceDone"].tap()
        XCTAssertTrue(app.screen("capture.heard").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your typed draft is kept. Add these tasks, then continue typing."].exists)
        app.screen("screen.capture").buttons["Add"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Keep typing this task")
        app.screen("screen.capture").buttons["Cancel"].tap()
        assertInboxCount("7 to triage", app: app)
        XCTAssertTrue(app.buttons["Water the ferns"].exists)
        XCTAssertFalse(app.buttons["Keep typing this task"].exists)
    }

    func testCancelWhileListeningNeverSavesInAutomaticMode() {
        let app = launch(route: "settings")
        chooseAutomaticSave(app)
        app.buttons["settings.done"].tap()
        app.waitForScreenToClose("screen.settings")
        app.dock("capture").press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["capture.voiceDone"].waitForExistence(timeout: 5))
        app.screen("screen.capture").buttons["Cancel"].tap()
        app.waitForScreenToClose("screen.capture")
        assertInboxCount("6 to triage", app: app)
    }

    func testVoicePreferenceSurvivesRelaunch() {
        let app = launch(route: "settings")
        chooseAutomaticSave(app)
        app.terminate()
        app.launch()
        app.waitForScreen("screen.settings")
        XCTAssertTrue(app.buttons["settings.afterVoiceCapture"].staticTexts["Save automatically"].exists)
    }

    private func launch(route: String = "today", transcript: String = "Water the ferns") -> XCUIApplication {
        let app = XCUIApplication.reviewSession(environment: ["OpenlistOpenRoute": route, "OpenlistVoiceFixture": transcript])
        app.launch()
        app.waitForScreen("screen.\(route)", timeout: 20)
        return app
    }

    private func chooseAutomaticSave(_ app: XCUIApplication) {
        app.buttons["settings.afterVoiceCapture"].tap()
        app.buttons["Save automatically"].tap()
    }

    private func assertInboxCount(_ count: String, app: XCUIApplication) {
        app.dock("inbox").tap()
        app.waitForScreen("screen.inbox")
        XCTAssertTrue(app.staticTexts[count].waitForExistence(timeout: 5))
    }
}
