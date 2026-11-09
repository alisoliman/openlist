//
//  KeyboardTyping.swift
//  OpenlistiOSUITests
//

import XCTest

/// `typeText` types on a virtual hardware keyboard. While one is attached,
/// iOS can minimize the on-screen keyboard, keeping it in the accessibility
/// tree below the screen, and about a second after the last key it detaches
/// the virtual keyboard and brings the on-screen one back. So straight after
/// typing, what rides on the keyboard, such as Capture's sheet or an alert,
/// may be about to slide, and `keyboards.firstMatch.exists` may hold with no
/// keyboard to see. Whether and when this happens varies by machine and run.
extension XCUIApplication {
    /// Whether a keyboard is on the screen, rather than minimized below it
    /// or gone. A snapshot, because a keyboard going away can vanish between
    /// two queries, which would fail the test; counted first, as a snapshot
    /// of no keyboard takes seconds to give up.
    var keyboardIsOnScreen: Bool {
        guard keyboards.count > 0, let keyboard = try? keyboards.firstMatch.snapshot() else { return false }
        return !keyboard.frame.isEmpty && keyboard.frame.minY < frame.maxY
    }

    /// Waits until a keyboard is on the screen.
    func waitForKeyboardToShow(timeout: TimeInterval = 10) -> Bool {
        poll(timeout) { keyboardIsOnScreen }
    }

    /// Waits until no keyboard is on the screen, for a field that lets it go.
    func waitForKeyboardToGo(timeout: TimeInterval = 10) -> Bool {
        poll(timeout) { !keyboardIsOnScreen }
    }

    /// Types `text` into `field`, which keeps its focus, then waits for the
    /// on-screen keyboard to be back if the typing put it away, so the next
    /// tap finds what rides on it where it stays. A keyboard that never shows
    /// (a hardware one connected) isn't waited for.
    func type(_ text: String, into field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        // Up already, or coming up after the tap that focused the field.
        let wasUp = poll(2) { keyboardIsOnScreen }
        field.typeText(text)
        guard wasUp else { return }
        XCTAssertTrue(poll(10) { keyboardIsOnScreen || keyboards.count == 0 },
                      "The keyboard didn't come back after typing", file: file, line: line)
    }

    /// Checks `condition` every tenth of a second until it holds or
    /// `timeout` passes.
    private func poll(_ timeout: TimeInterval, until condition: () -> Bool) -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            guard Date.now < deadline else { return false }
            usleep(100_000)
        }
        return true
    }
}
