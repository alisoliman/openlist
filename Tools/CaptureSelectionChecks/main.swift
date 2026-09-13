import AppKit
import SwiftUI

let app = NSApplication.shared
// This fixture is never ordered on screen and does not activate the app.
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
let editor = CaptureTitleNSTextView(frame: NSRect(x: 0, y: 80, width: 500, height: 80))
editor.isRichText = false
editor.isEditable = true
editor.isSelectable = true
editor.allowsUndo = true
let search = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
window.contentView!.addSubview(editor)
window.contentView!.addSubview(search)
let focus = CaptureTitleFocus()
editor.captureFocus = focus
focus.view = editor
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}
func roundTrip(text: String, range: NSRange, insertion: String, expected: String) {
    editor.string = text
    window.makeFirstResponder(editor)
    editor.setSelectedRange(range)
    focus.preserveSelection()
    window.makeFirstResponder(search)
    focus.restoreSelection()
    check(window.firstResponder === editor, "Focus returns to the actual capture text view")
    check(editor.selectedRange() == range, "Native selection survives destination search focus")
    editor.insertText(insertion, replacementRange: editor.selectedRange())
    check(editor.string == expected, "Typing after destination selection inserts at prior caret or replaces only chosen substring")
}
roundTrip(text: "alpha omega tomorrow", range: NSRange(location: 6, length: 0), insertion: "NEW ", expected: "alpha NEW omega tomorrow")
roundTrip(text: "alpha omega tomorrow", range: NSRange(location: 6, length: 5), insertion: "NEW", expected: "alpha NEW tomorrow")
let unicode = "🌍 alpha omega tomorrow"
let omega = (unicode as NSString).range(of: "omega")
roundTrip(text: unicode, range: NSRange(location: omega.location, length: 0), insertion: "NEW ", expected: "🌍 alpha NEW omega tomorrow")
editor.string = "alpha omega"
editor.setSelectedRange(NSRange(location: 3, length: 0))
focus.preserveSelection()
focus.restoreSelection()
check(editor.selectedRange() == NSRange(location: 3, length: 0), "Metadata edits retain native insertion point")
var submissions = 0
editor.submit = { submissions += 1 }
func key(_ code: UInt16, modifiers: NSEvent.ModifierFlags = [], characters: String = "\r") -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
}
editor.keyDown(with: key(36))
check(submissions == 1 && editor.string == "alpha omega", "Return submits without inserting a new line")
editor.keyDown(with: key(36, modifiers: .shift))
check(submissions == 1 && editor.string.contains("\n"), "Shift Return adds a line without submitting")
print("Passed \(checks) native capture selection checks (hidden window)")
