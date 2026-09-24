// Checks the inspector's title and note text views (NXInspectorText): the
// design's line boxes, a completed title's strike, the note's and the
// title's keys, a title kept to one line, text at rest shown alone, and the
// focus a view taken away gives back. Compiled against the real
// openlist/Next/NextInspectorText.swift by Tools/run-inspector-text-checks.sh.

import AppKit
import SwiftUI

var failures = 0, checks = 0

@MainActor
func check(_ c: Bool, _ label: String, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if !c { failures += 1; print("FAIL  \(label)\(detail().isEmpty ? "" : " — \(detail())")") }
}

func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.01 }

/// Lets queued main-queue work, like the focus report, run.
@MainActor
func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

@MainActor
final class Box { var text = "" }

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                          backing: .buffered, defer: false)
    let host = NSView(frame: window.contentLayoutRect)
    window.contentView = host

    @MainActor func view(_ role: NXInspectorText.Role, _ text: String = "", width: CGFloat = 300) -> NXInspectorTextView {
        let view = NXInspectorTextView.make(role: role)
        view.show(text)
        view.frame = NSRect(x: 0, y: 0, width: width, height: view.height(fittingWidth: width))
        host.addSubview(view)
        return view
    }

    // One line in the design's box, and each more a box further down:
    // 13/1.55 for the note, 18/1.3 for the title.
    for (role, box) in [(NXInspectorText.Role.note, 13 * 1.55), (.title, 18 * 1.3)] as [(NXInspectorText.Role, CGFloat)] {
        check(close(NXInspectorTextView.lineBox(role), box), "\(role) line box")
        for count in 1...4 {
            let text = Array(repeating: "Hg", count: count).joined(separator: "\n")
            let lines = NXInspectorTextView.make(role: role)
            lines.show(text)
            let height = lines.height(fittingWidth: 300)
            check(close(height, CGFloat(count) * box), "\(count) \(role) lines stand \(count) boxes", "\(height) against \(CGFloat(count) * box)")
        }
        // A line wrapped at the panel's width falls on the same pitch.
        let long = NXInspectorTextView.make(role: role)
        long.show(String(repeating: "Wrapped words go on ", count: 8))
        let height = long.height(fittingWidth: 180)
        let lines = height / box
        check(lines >= 2 && close(lines, lines.rounded()), "wrapped \(role) lines fall on its pitch", "\(height)")
        check(close(NXInspectorTextView.make(role: role).height(fittingWidth: 300), box), "an empty \(role) is one box tall")
    }

    // A completed task's title: grey and struck, what's typed too.
    let title = view(.title, "Buy milk")
    check(title.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) == nil, "an open title isn't struck")
    title.isDone = true
    check((title.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue,
          "a done title is struck")
    check((title.typingAttributes[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue, "what's typed in a done title is struck")
    let doneColor = title.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    check(close(doneColor?.alphaComponent ?? 0, 0.45), "a done title is ink 0.45")
    title.isDone = false
    check(title.textStorage?.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) == nil, "a reopened title isn't struck")
    // Text put back in another colour, as Undo can, takes the title's.
    title.textStorage?.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: 3))
    title.restyle()
    check((title.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) === NXEditor.ink,
          "restyled text takes the title's ink")

    // The title stays one line: every break finishes it, and typed, pasted
    // or dropped breaks become spaces.
    check(NXInspectorTextView.oneLine("a\r\nb\nc\rd\u{2028}e") == "a b c d e", "each break is a space, \\r\\n one")
    for selector in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
                     #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertParagraphSeparator(_:))] {
        check(window.makeFirstResponder(title), "the title takes the keyboard")
        title.setSelectedRange(NSRange(location: title.string.utf16.count, length: 0))
        title.doCommand(by: selector)
        check(title.string == "Buy milk", "\(selector) adds no break to the title", title.string)
        check(window.firstResponder !== title, "\(selector) finishes the title")
    }
    check(window.makeFirstResponder(title), "the title takes the keyboard again")
    title.setSelectedRange(NSRange(location: title.string.utf16.count, length: 0))
    title.insertText(" and\neggs", replacementRange: NSRange(location: NSNotFound, length: 0))
    check(title.string == "Buy milk and eggs", "typed breaks become spaces", title.string)
    let board = NSPasteboard(name: NSPasteboard.Name("InspectorTextChecks-\(UUID().uuidString)"))
    board.clearContents()
    board.setString(" bread\nbutter\r\njam", forType: .string)
    title.setSelectedRange(NSRange(location: title.string.utf16.count, length: 0))
    check(title.readSelection(from: board, type: .string), "the title reads a paste")
    check(title.string == "Buy milk and eggs bread butter jam", "pasted breaks become spaces", title.string)
    board.releaseGlobally()
    var switched = 0
    title.onSwitch = { switched += 1 }
    title.doCommand(by: #selector(NSResponder.insertTab(_:)))
    check(switched == 1 && !title.string.contains("\t"), "Tab goes on from the title")
    title.onSwitch = nil
    // As the next key would, after the event that typed.
    settle()
    check(window.undoManager?.canUndo == true, "typing is undoable while the title is written")
    title.doCommand(by: #selector(NSResponder.insertTab(_:)))
    check(window.firstResponder !== title && !title.string.contains("\t"), "Tab finishes a title with no note to go to")
    check(window.undoManager?.canUndo == false, "finishing the title leaves no typing to undo")

    // The note keeps the document note's keys.
    let note = view(.note, "First")
    var focus: [Bool] = []
    note.onFocus = { focus.append($0) }
    check(window.makeFirstResponder(note), "the note takes the keyboard")
    settle()
    check(focus == [true], "the note says it has the keyboard", "\(focus)")
    check(note.acceptableDragTypes == [.string], "text drops go into the note being written")
    note.setSelectedRange(NSRange(location: note.string.utf16.count, length: 0))
    note.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    check(note.string == "First\n" && window.firstResponder === note, "Return breaks the note's line", note.string)
    settle()
    note.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    check(window.firstResponder !== note, "Esc finishes the note")
    settle()
    check(focus == [true, false], "the note says it let the keyboard go", "\(focus)")
    check(note.acceptableDragTypes.isEmpty, "a drop on the note at rest is the panel's")
    for (flags, code) in [(NSEvent.ModifierFlags.command, UInt16(36)), (.command, 76)] {
        check(window.makeFirstResponder(note), "the note takes the keyboard for ⌘Return")
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, characters: "\r",
                                     charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: code)!
        check(note.performKeyEquivalent(with: event), "⌘Return is the note's before the menus'")
        check(window.firstResponder !== note && note.string == "First\n", "⌘Return finishes the note")
    }
    check(window.makeFirstResponder(note), "the note takes the keyboard for Tab")
    note.doCommand(by: #selector(NSResponder.insertTab(_:)))
    check(window.firstResponder !== note && !note.string.contains("\t"), "Tab finishes the note")
    check(window.makeFirstResponder(note), "the note takes the keyboard for ⇧Tab")
    var back = 0
    note.onSwitch = { back += 1 }
    note.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
    check(back == 1, "⇧Tab goes back from the note to the title")
    let plain = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                 windowNumber: window.windowNumber, context: nil, characters: "\r",
                                 charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
    check(!note.performKeyEquivalent(with: plain), "Return alone is no key equivalent")

    // At rest the text shows alone, as the design's static text: what was
    // selected, and what was marked misspelled, go with the edit.
    let rest = view(.note, "Buy mlik")
    check(!rest.isContinuousSpellCheckingEnabled, "a note at rest checks no spelling")
    check(window.makeFirstResponder(rest), "the note takes the keyboard to be checked")
    check(rest.isContinuousSpellCheckingEnabled, "the note checks spelling while written")
    rest.setSelectedRange(NSRange(location: 0, length: 3))
    rest.layoutManager?.addTemporaryAttribute(.spellingState, value: 1, forCharacterRange: NSRange(location: 4, length: 4))
    rest.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    check(rest.selectedRange() == NSRange(location: 3, length: 0), "Esc leaves no selection showing", "\(rest.selectedRange())")
    check(rest.layoutManager?.temporaryAttribute(.spellingState, atCharacterIndex: 5, effectiveRange: nil) == nil,
          "Esc leaves no spelling marks")
    check(!rest.isContinuousSpellCheckingEnabled, "a finished note checks no spelling")
    check(window.makeFirstResponder(rest), "the note takes the keyboard to be selected")
    rest.selectAll(nil)
    // As a click off the field, or Tab, lets it go.
    window.makeFirstResponder(nil)
    check(rest.selectedRange() == NSRange(location: 8, length: 0), "letting go leaves no selection showing", "\(rest.selectedRange())")
    // Edit ▸ Spelling turned off while written stays off the next time.
    check(window.makeFirstResponder(rest), "the note takes the keyboard for Edit ▸ Spelling")
    rest.isContinuousSpellCheckingEnabled = false
    window.makeFirstResponder(nil)
    check(window.makeFirstResponder(rest) && !rest.isContinuousSpellCheckingEnabled, "spelling turned off stays off")
    window.makeFirstResponder(nil)
    let unchecked = view(.title, "Buy mlik")
    check(window.makeFirstResponder(unchecked) && !unchecked.isContinuousSpellCheckingEnabled, "the title checks no spelling")
    window.makeFirstResponder(nil)
    // One line that Return finishes reads as a field.
    check(unchecked.accessibilityRole() == .textField, "the title reads as a text field")
    check(rest.accessibilityRole() == .textArea, "the note reads as a text area")

    // What was typed goes as the edit's one step, not as typing under it.
    let undo = view(.note)
    check(window.makeFirstResponder(undo), "a fresh note takes the keyboard")
    undo.insertText("typed", replacementRange: NSRange(location: NSNotFound, length: 0))
    settle()
    check(window.undoManager?.canUndo == true, "typing is undoable while the note is written")
    window.makeFirstResponder(nil)
    check(window.undoManager?.canUndo == false, "finishing the note leaves no typing to undo")

    // Taken away while written, as the panel moves on, its typing goes too.
    let dropped = view(.title)
    check(window.makeFirstResponder(dropped), "a fresh title takes the keyboard")
    dropped.insertText("typed", replacementRange: NSRange(location: NSNotFound, length: 0))
    settle()
    dropped.removeFromSuperview()
    check(window.undoManager?.canUndo == true, "typing outlives a view taken away")
    NXInspectorText.dismantleNSView(dropped, coordinator: NXInspectorText.Coordinator())
    check(window.undoManager?.canUndo == false, "a view taken away leaves no typing to undo")

    // Hosted as the panel hosts it: typing reaches the draft, and the view
    // stands its lines' boxes tall.
    let box = Box()
    box.text = "One\nTwo"
    let fields = NXInspectorFields()
    let hosting = NSHostingView(rootView: NXInspectorText(role: .note, text: Binding(get: { box.text }, set: { box.text = $0 }),
                                                          caretColor: .systemPurple, fields: fields, onFocus: { _ in })
                                    .frame(width: 300))
    hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
    host.addSubview(hosting)
    hosting.layoutSubtreeIfNeeded()
    let hostedHeight = hosting.fittingSize.height
    check(hostedHeight == (2 * 13 * 1.55).rounded(.up), "a hosted two-line note stands two boxes tall", "\(hostedHeight)")
    fields.write(.note)
    let hosted = window.firstResponder as? NXInspectorTextView
    check(hosted?.string == "One\nTwo" && hosted?.selectedRange().location == 7, "the note takes the caret at its end")
    hosted?.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
    check(box.text == "One\nTwo!", "typing reaches the draft", box.text)
    window.makeFirstResponder(nil)

    // Taken away while written, as the panel's title is for another task,
    // the view says it let the keyboard go, unless the one in its place has
    // it by then.
    var titleFocus: [Bool] = []
    let titleFields = NXInspectorFields()
    let titleView = { (key: Int) in
        AnyView(NXInspectorText(role: .title, text: .constant("Task \(key)"), caretColor: .systemPurple, fields: titleFields,
                                onFocus: { titleFocus.append($0) })
            .id(key)
            .frame(width: 300))
    }
    let swapping = NSHostingView(rootView: titleView(1))
    swapping.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
    host.addSubview(swapping)
    swapping.layoutSubtreeIfNeeded()
    titleFields.write(.title)
    settle()
    check(titleFocus == [true], "the hosted title says it has the keyboard", "\(titleFocus)")
    swapping.rootView = titleView(2)
    swapping.layoutSubtreeIfNeeded()
    settle()
    check(titleFocus == [true, false], "a title taken away while written says it let go", "\(titleFocus)")
    titleFields.write(.title)
    settle()
    check((window.firstResponder as? NXInspectorTextView)?.string == "Task 2" && titleFocus == [true, false, true],
          "the title in its place takes the keyboard", "\(titleFocus)")
    swapping.rootView = titleView(3)
    swapping.layoutSubtreeIfNeeded()
    titleFields.write(.title)
    settle()
    check((window.firstResponder as? NXInspectorTextView)?.string == "Task 3" && titleFocus.last == true
            && titleFocus.count == 4, "one taken away doesn't take the focus from the one in its place", "\(titleFocus)")
}

print(failures == 0 ? "✅ \(checks) inspector text checks passed" : "❌ \(failures)/\(checks) failed")
exit(failures == 0 ? 0 : 1)
