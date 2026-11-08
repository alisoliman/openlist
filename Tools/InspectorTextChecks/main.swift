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

    // One line in its box, and each more a box further down: 13.5/1.6 for
    // the note, 20/1.25 for the title, and the page's 14.5/1.65 note.
    let sizes: [(role: NXInspectorText.Role, large: Bool, box: CGFloat)] = [
        (.note, false, 13.5 * 1.6), (.title, false, 20 * 1.25), (.note, true, 14.5 * 1.65),
    ]
    for (role, large, box) in sizes {
        let name = large ? "page \(role)" : "\(role)"
        func make() -> NXInspectorTextView {
            let view = NXInspectorTextView.make(role: role)
            if large { view.setSize(large: true, serif: false) }
            return view
        }
        check(close(NXInspectorTextView.metrics(role, large: large).lineBox, box), "\(name) line box")
        for count in 1...4 {
            let text = Array(repeating: "Hg", count: count).joined(separator: "\n")
            let lines = make()
            lines.show(text)
            let height = lines.height(fittingWidth: 300)
            check(close(height, CGFloat(count) * box), "\(count) \(name) lines stand \(count) boxes", "\(height) against \(CGFloat(count) * box)")
        }
        // A line wrapped at the panel's width falls on the same pitch.
        let long = make()
        long.show(String(repeating: "Wrapped words go on ", count: 8))
        let height = long.height(fittingWidth: 180)
        let lines = height / box
        check(lines >= 2 && close(lines, lines.rounded()), "wrapped \(name) lines fall on its pitch", "\(height)")
        check(close(make().height(fittingWidth: 300), box), "an empty \(name) is one box tall")
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
    // Laid out on the display's pixels, which round it up a fraction of a point.
    check(hostedHeight >= 2 * 13.5 * 1.6 && hostedHeight - 2 * 13.5 * 1.6 < 1, "a hosted two-line note stands two boxes tall", "\(hostedHeight)")
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
    window.makeFirstResponder(nil)

    // MARK: The note as a document

    func hidden(_ view: NXInspectorTextView, _ piece: String, nth: Int = 0) -> Bool {
        let source = view.string as NSString
        var range = NSRange(location: 0, length: 0), from = 0
        for _ in 0...nth {
            range = source.range(of: piece, range: NSRange(location: from, length: source.length - from))
            from = NSMaxRange(range)
        }
        guard range.location != NSNotFound, let storage = view.textStorage else { return false }
        var all = true
        storage.enumerateAttribute(.font, in: range) { value, _, _ in
            if ((value as? NSFont)?.pointSize ?? 99) > 1 { all = false }
        }
        return all
    }
    func caret(_ view: NXInspectorTextView, at location: Int) {
        view.setSelectedRange(NSRange(location: location, length: 0))
        view.selectionDidChangeInNote()
    }

    // A line's own syntax is out of sight, at rest and while written; an
    // inline construct's shows only while the caret is inside it.
    let doc = view(.note, "## Plan\nGet **cash** first\n- [ ] Pay\n> said")
    check(hidden(doc, "## ") && hidden(doc, "- [ ] ") && hidden(doc, "> ") && hidden(doc, "**"), "at rest no syntax shows")
    check(!hidden(doc, "Plan") && !hidden(doc, "cash") && !hidden(doc, "Pay"), "the words show")
    check(window.makeFirstResponder(doc), "the document note takes the keyboard")
    caret(doc, at: 3)
    check(hidden(doc, "## ") && hidden(doc, "- [ ] ") && hidden(doc, "**"), "written, a line's syntax stays out of sight")
    caret(doc, at: (doc.string as NSString).range(of: "cash").location + 2)
    check(!hidden(doc, "**") && !hidden(doc, "**", nth: 1) && hidden(doc, "## "), "the caret in bold shows its markers, and only its")
    let kinds = (doc.layoutManager as? NXNoteLayoutManager)?.decorations.map { "\($0.kind)" } ?? []
    check(kinds.contains { $0.hasPrefix("box") } && kinds.contains("quote"), "a box and a quote's rule are drawn", "\(kinds)")

    // The caret never rests in a line's hidden syntax.
    let item = (doc.string as NSString).range(of: "- [ ] Pay")
    let snapped = doc.snapped([NSValue(range: NSRange(location: item.location + 2, length: 0))], from: [])
    check(snapped.first?.rangeValue.location == item.location + 6, "a caret in a box's syntax goes to its words")
    let stepBack = doc.snapped([NSValue(range: NSRange(location: item.location + 5, length: 0))],
                               from: [NSValue(range: NSRange(location: item.location + 6, length: 0))])
    check(stepBack.first?.rangeValue.location == item.location - 1, "stepping back from an item's words goes to the line before")

    // Backspace at an item's words takes its box off; Tab and ⇧Tab nest it.
    caret(doc, at: item.location + 6)
    doc.doCommand(by: #selector(NSResponder.insertTab(_:)))
    check(doc.string.contains("\n  - [ ] Pay") && window.firstResponder === doc, "Tab nests a list item", doc.string)
    doc.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
    check(doc.string.contains("\n- [ ] Pay"), "⇧Tab takes it back out", doc.string)
    caret(doc, at: item.location + 6)
    doc.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
    check(doc.string.contains("\nPay\n") && doc.selectedRange().location == item.location, "Backspace on its words takes the box off", doc.string)

    // A box ticks with a click at rest, as one step saved at once.
    let boxes = view(.note, "- [ ] Pay\n- [x] Book")
    var commits = 0
    boxes.onCommit = { commits += 1 }
    boxes.toggleBox(at: 0)
    check(boxes.string == "- [x] Pay\n- [x] Book" && commits == 1, "a box at rest ticks and saves", boxes.string)
    func wordsWidth(_ view: NXInspectorTextView, _ piece: String) -> CGFloat {
        guard let layout = view.layoutManager, let container = view.textContainer else { return 0 }
        layout.ensureLayout(for: container)
        let range = (view.string as NSString).range(of: piece)
        return layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container).width
    }
    check(wordsWidth(boxes, "Pay") > 15, "a ticked item's words keep their width", "\(wordsWidth(boxes, "Pay"))")
    boxes.toggleBox(at: 10)
    check(boxes.string == "- [x] Pay\n- [ ] Book" && commits == 2, "a ticked box unticks", boxes.string)
    if let layout = boxes.layoutManager as? NXNoteLayoutManager, let first = layout.decorations.first,
       let rect = layout.boxRect(for: first) {
        let point = CGPoint(x: rect.midX + boxes.textContainerOrigin.x, y: rect.midY + boxes.textContainerOrigin.y)
        check(boxes.noteWidget(at: point, command: false) == .box(0), "a click on the box lands on it")
    } else {
        check(false, "the box is laid out")
    }

    // Typing: `[]` and a space make a checklist item, Return after a fence
    // opens a block, and `/` opens the menu that turns the line.
    let typed = view(.note, "")
    var slashes: [NXNoteSlash?] = []
    typed.onSlash = { slashes.append($0) }
    check(window.makeFirstResponder(typed), "a fresh note takes the keyboard to be typed in")
    for character in ["[", "]", " ", "P", "a", "y"] { typed.insertText(character, replacementRange: NSRange(location: NSNotFound, length: 0)) }
    check(typed.string == "- [ ] Pay", "a space after [] makes a checklist item", typed.string)
    typed.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    check(typed.string == "- [ ] Pay\n- [ ] ", "Return starts the next item", typed.string)
    typed.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    check(typed.string == "- [ ] Pay\n", "Return on an empty item ends the list", typed.string)
    typed.insertText("/", replacementRange: NSRange(location: NSNotFound, length: 0))
    check(typed.slash != nil && slashes.last??.query == "", "a / on a line of its own opens the menu")
    for character in ["c", "h", "e"] { typed.insertText(character, replacementRange: NSRange(location: NSNotFound, length: 0)) }
    check(typed.slash?.query == "che" && typed.slash?.blocks == [.checklist], "the menu follows what's typed", "\(String(describing: typed.slash))")
    typed.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    check(typed.string == "- [ ] Pay\n- [ ] " && typed.slash == nil && slashes.last == .some(nil), "Return turns the line and closes the menu",
          typed.string)
    typed.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    typed.insertText("/", replacementRange: NSRange(location: NSNotFound, length: 0))
    typed.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
    check(typed.slash == nil && window.firstResponder === typed, "Esc closes the menu and keeps the note")
    typed.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
    typed.insertText("```", replacementRange: NSRange(location: NSNotFound, length: 0))
    typed.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    check(typed.string.hasSuffix("```\n\n```") && typed.selectedRange().location == (typed.string as NSString).length - 4,
          "Return after a fence opens a block and closes it", typed.string)

    // Words typed into a checklist item keep their spaces, written and at rest.
    let spaced = view(.note, "Intro")
    check(window.makeFirstResponder(spaced), "a note takes the keyboard for an item")
    spaced.setSelectedRange(NSRange(location: 5, length: 0))
    spaced.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    for character in ["/", "c", "h", "e"] { spaced.insertText(character, replacementRange: NSRange(location: NSNotFound, length: 0)) }
    spaced.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    for character in "Return the copy".map(String.init) { spaced.insertText(character, replacementRange: NSRange(location: NSNotFound, length: 0)) }
    window.makeFirstResponder(nil)
    spaced.toggleBox(at: 6)
    let itemWords = (spaced.string as NSString).range(of: "Return the copy")
    var tiny: [Int] = []
    for index in itemWords.location..<NSMaxRange(itemWords) {
        if ((spaced.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.pointSize ?? 0) < 1 { tiny.append(index) }
    }
    check(spaced.string == "Intro\n- [x] Return the copy" && tiny.isEmpty, "an item's typed words keep their face", "\(spaced.string.debugDescription) \(tiny)")

    // Words: an address pasted over them links them, and Bold wraps them.
    let words = view(.note, "Booking through Fujiya Hotel today")
    check(window.makeFirstResponder(words), "the note takes the keyboard to be linked")
    let hotel = (words.string as NSString).range(of: "Fujiya Hotel")
    words.setSelectedRange(hotel)
    let linkBoard = NSPasteboard(name: NSPasteboard.Name("InspectorTextChecks-link-\(UUID().uuidString)"))
    linkBoard.clearContents()
    linkBoard.setString("https://www.fujiyahotel.jp/en/", forType: .string)
    check(words.readSelection(from: linkBoard, type: .string), "an address pasted over words is taken")
    check(words.string == "Booking through [Fujiya Hotel](https://www.fujiyahotel.jp/en/) today", "and links them", words.string)
    linkBoard.releaseGlobally()
    let today = (words.string as NSString).range(of: "today")
    words.setSelectedRange(today)
    words.toggleBold(nil)
    check(words.string.hasSuffix("**today**") && words.selectedRange().length == 5, "Bold wraps the words", words.string)
    words.toggleBold(nil)
    check(words.string.hasSuffix(" today"), "Bold again unwraps them", words.string)
    window.makeFirstResponder(nil)
    let live = (words.string as NSString).range(of: "Fujiya Hotel")
    check(words.textStorage?.attribute(.link, at: live.location, effectiveRange: nil) != nil, "at rest a link is live")
    check(window.makeFirstResponder(words)
          && words.textStorage?.attribute(.link, at: live.location, effectiveRange: nil) == nil
          && words.textStorage?.attribute(.nxNoteAddress, at: live.location, effectiveRange: nil) != nil,
          "written, a link takes ⌘-click, so a click places the caret")
    window.makeFirstResponder(nil)

    // A link alone on its line is a bookmark: its address out of sight under
    // a card named from the address, until the caret's on the line.
    let maps = "https://www.google.com/maps/place/Hakone+Yumoto+Onsen/@35.23,139.10,15z"
    let card = view(.note, "Where:\n\(maps)")
    let cardKinds = (card.layoutManager as? NXNoteLayoutManager)?.decorations.map { "\($0.kind)" } ?? []
    check(cardKinds.contains { $0.contains("Hakone Yumoto Onsen") && $0.contains("google.com/maps") }, "a bookmark's card names it",
          "\(cardKinds)")
    let address = (card.string as NSString).range(of: maps)
    check((card.textStorage?.attribute(.foregroundColor, at: address.location, effectiveRange: nil) as? NSColor) == NSColor.clear,
          "its address is out of sight")
    check(window.makeFirstResponder(card), "the bookmark's note takes the keyboard")
    caret(card, at: NSMaxRange(address))
    check((card.textStorage?.attribute(.foregroundColor, at: address.location, effectiveRange: nil) as? NSColor) != NSColor.clear,
          "with the caret on its line, the address shows to be written")
    window.makeFirstResponder(nil)
}

print(failures == 0 ? "✅ \(checks) inspector text checks passed" : "❌ \(failures)/\(checks) failed")
exit(failures == 0 ? 0 : 1)
